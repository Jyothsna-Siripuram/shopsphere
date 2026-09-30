require "rails_helper"

RSpec.describe Auth::AccessToken do
  let(:user) { create(:user) }

  it "round-trips the user id as the subject claim" do
    token = described_class.encode(user)

    expect(described_class.subject_id(token)).to eq(user.id.to_s)
  end

  it "rejects a token whose signature was made with a different key" do
    forged = JWT.encode(
      { sub: user.id.to_s, iss: "shopsphere", iat: Time.current.to_i,
        exp: 15.minutes.from_now.to_i },
      "not-the-real-secret",
      "HS256"
    )

    expect { described_class.decode(forged) }.to raise_error(described_class::InvalidToken)
  end

  # The alg-confusion family: a forged token declares alg:"none" so a naive
  # verifier skips signature checking entirely. Pinning the algorithm on decode
  # is the mitigation, and this spec is what proves it is actually in force.
  it "rejects an unsigned token claiming the none algorithm" do
    forged = JWT.encode(
      { sub: user.id.to_s, iss: "shopsphere", iat: Time.current.to_i,
        exp: 15.minutes.from_now.to_i },
      nil,
      "none"
    )

    expect { described_class.decode(forged) }.to raise_error(described_class::InvalidToken)
  end

  it "rejects an expired token" do
    token = travel_to(1.hour.ago) { described_class.encode(user) }

    expect { described_class.decode(token) }.to raise_error(described_class::InvalidToken)
  end

  it "rejects a token issued by a different issuer" do
    foreign = JWT.encode(
      { sub: user.id.to_s, iss: "somewhere-else", iat: Time.current.to_i,
        exp: 15.minutes.from_now.to_i },
      Rails.application.config.x.jwt_secret_key,
      "HS256"
    )

    expect { described_class.decode(foreign) }.to raise_error(described_class::InvalidToken)
  end

  it "rejects a blank or malformed token" do
    expect { described_class.decode(nil) }.to raise_error(described_class::InvalidToken)
    expect { described_class.decode("not.a.jwt") }.to raise_error(described_class::InvalidToken)
  end

  # Role is deliberately absent so a demoted administrator loses access
  # immediately rather than when their token expires.
  it "carries no authorization claims" do
    payload = described_class.decode(described_class.encode(user))

    expect(payload.keys).to contain_exactly("sub", "iss", "iat", "exp", "jti")
  end
end
