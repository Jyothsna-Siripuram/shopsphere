module Auth
  # Issues an access/refresh pair for a newly authenticated session.
  #
  # `family_id` groups every refresh token descended from one login, which is
  # what lets reuse detection revoke a whole compromised lineage rather than a
  # single token.
  class IssueTokenPair
    Result = Struct.new(:access_token, :refresh_token, :refresh_record, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(user:, family_id: SecureRandom.uuid, user_agent: nil, client_ip: nil)
      @user = user
      @family_id = family_id
      @user_agent = user_agent
      @client_ip = client_ip
    end

    def call
      record, raw = RefreshToken.issue!(
        user: user, family_id: family_id, user_agent: user_agent, client_ip: client_ip
      )

      Result.new(
        access_token: AccessToken.encode(user),
        refresh_token: raw,
        refresh_record: record
      )
    end

    private

    attr_reader :user, :family_id, :user_agent, :client_ip
  end
end
