class RefreshToken < ApplicationRecord
  # 32 bytes of CSPRNG output. Encoded urlsafe base64 it becomes a 43-character
  # opaque string — enough entropy that guessing is not a threat model.
  TOKEN_BYTES = 32
  LIFETIME = 30.days

  belongs_to :user, inverse_of: :refresh_tokens

  validates :token_digest, presence: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :family_id, :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where(arel_table[:expires_at].gt(Time.current)) }

  # Deterministic so a presented token can be looked up by index rather than
  # compared row by row. See the migration for why this is SHA-256, not bcrypt.
  def self.digest_for(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.generate_raw_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end

  # Returns [record, raw_token]. The raw token exists only in this return value
  # and in the response cookie; it is never stored or logged.
  def self.issue!(user:, family_id: SecureRandom.uuid, user_agent: nil, client_ip: nil)
    raw = generate_raw_token
    record = create!(
      user: user,
      token_digest: digest_for(raw),
      family_id: family_id,
      expires_at: LIFETIME.from_now,
      user_agent: user_agent&.truncate(255),
      client_ip: client_ip
    )
    [ record, raw ]
  end

  def self.find_by_raw_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest_for(raw_token))
  end

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  def revoke!(reason)
    return if revoked_at.present?

    update!(revoked_at: Time.current, revoked_reason: reason)
  end
end
