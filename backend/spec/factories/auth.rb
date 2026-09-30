FactoryBot.define do
  factory :refresh_token do
    user
    family_id { SecureRandom.uuid }
    expires_at { RefreshToken::LIFETIME.from_now }
    # A valid digest by default; specs that need the raw token use
    # RefreshToken.issue! instead, which returns both halves.
    token_digest { RefreshToken.digest_for(SecureRandom.urlsafe_base64(32)) }

    trait :revoked do
      revoked_at { Time.current }
      revoked_reason { "rotated" }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end
