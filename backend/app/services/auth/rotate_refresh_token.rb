module Auth
  # Exchanges a refresh token for a new pair, rotating the presented token.
  #
  # Rotation plus reuse detection is the OAuth 2.0 Security BCP pattern, and it
  # is what makes a stolen refresh token self-limiting. Without rotation, a
  # token exfiltrated once grants access for its entire 30-day lifetime and
  # nothing ever reveals the theft.
  #
  # The threat it closes:
  #
  #   1. An attacker steals refresh token R.
  #   2. Either party redeems R first; R is revoked and R' issued.
  #   3. The other party redeems R again.
  #   4. A revoked-but-recently-rotated token being presented means two parties
  #      hold it. We cannot tell which is the thief, so we revoke the entire
  #      family and force both to re-authenticate.
  #
  # The legitimate user notices a surprise logout. The attacker loses access.
  # That trade is correct: a false positive costs one login, a false negative
  # costs the account.
  class RotateRefreshToken
    class InvalidRefreshToken < StandardError; end
    class ReuseDetected < InvalidRefreshToken; end

    def self.call(...) = new(...).call

    def initialize(raw_token:, user_agent: nil, client_ip: nil)
      @raw_token = raw_token
      @user_agent = user_agent
      @client_ip = client_ip
    end

    def call
      existing = RefreshToken.find_by_raw_token(raw_token)
      raise InvalidRefreshToken, "unknown token" if existing.nil?

      reuse_detected = false

      # The family revocation must COMMIT, so nothing may raise inside this
      # block. Raising here would roll the transaction back and undo the very
      # revocation that reuse detection exists to perform — the security control
      # would appear to work while changing nothing.
      pair = RefreshToken.transaction do
        # Lock before inspecting state: two simultaneous refreshes presenting the
        # same token would otherwise both read it as active and both rotate,
        # issuing two valid tokens from one.
        existing.lock!

        if existing.revoked_at.present?
          revoke_family!(existing)
          reuse_detected = true
          nil
        elsif existing.expires_at <= Time.current
          nil
        else
          existing.revoke!("rotated")

          IssueTokenPair.call(
            user: existing.user,
            family_id: existing.family_id,
            user_agent: user_agent,
            client_ip: client_ip
          )
        end
      end

      # Raised only after the transaction has committed.
      raise ReuseDetected, "refresh token reuse detected" if reuse_detected
      raise InvalidRefreshToken, "expired token" if pair.nil?

      pair
    end

    private

    attr_reader :raw_token, :user_agent, :client_ip

    # A token already consumed by rotation is being presented again, so two
    # parties hold it. We cannot tell which, so the whole lineage dies.
    def revoke_family!(token)
      RefreshToken.where(family_id: token.family_id, revoked_at: nil)
                  .update_all(revoked_at: Time.current, revoked_reason: "reuse_detected")

      Rails.logger.warn(
        event: "refresh_token_reuse_detected",
        user_id: token.user_id,
        family_id: token.family_id,
        client_ip: client_ip
      )
    end
  end
end
