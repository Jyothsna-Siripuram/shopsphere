require "rails_helper"

RSpec.describe Auth::RotateRefreshToken do
  let(:user) { create(:user) }

  def issue_for(user)
    Auth::IssueTokenPair.call(user: user)
  end

  describe "rotation" do
    it "revokes the presented token and issues a replacement" do
      original = issue_for(user)

      rotated = described_class.call(raw_token: original.refresh_token)

      expect(original.refresh_record.reload).to have_attributes(
        revoked_at: be_present, revoked_reason: "rotated"
      )
      expect(rotated.refresh_token).not_to eq(original.refresh_token)
      expect(rotated.refresh_record).to be_active
    end

    it "keeps the replacement in the same family, so lineage survives rotation" do
      original = issue_for(user)

      rotated = described_class.call(raw_token: original.refresh_token)

      expect(rotated.refresh_record.family_id).to eq(original.refresh_record.family_id)
    end

    it "returns a usable access token for the same user" do
      original = issue_for(user)

      rotated = described_class.call(raw_token: original.refresh_token)

      expect(Auth::AccessToken.subject_id(rotated.access_token)).to eq(user.id.to_s)
    end
  end

  describe "reuse detection" do
    # The core security property: a stolen refresh token becomes worthless as
    # soon as either party redeems it twice.
    it "revokes the entire family when an already-rotated token is replayed" do
      original = issue_for(user)
      second = described_class.call(raw_token: original.refresh_token)
      third = described_class.call(raw_token: second.refresh_token)

      expect { described_class.call(raw_token: original.refresh_token) }
        .to raise_error(described_class::ReuseDetected)

      # Every descendant is dead, not just the replayed token, because we cannot
      # tell which holder is the attacker.
      expect(third.refresh_record.reload.revoked_reason).to eq("reuse_detected")
      expect(RefreshToken.where(family_id: original.refresh_record.family_id).active).to be_empty
    end

    it "does not touch other families belonging to the same user" do
      compromised = issue_for(user)
      other_device = issue_for(user)
      described_class.call(raw_token: compromised.refresh_token)

      expect { described_class.call(raw_token: compromised.refresh_token) }
        .to raise_error(described_class::ReuseDetected)

      expect(other_device.refresh_record.reload).to be_active
    end
  end

  describe "rejection" do
    it "rejects an unknown token" do
      expect { described_class.call(raw_token: "never-issued") }
        .to raise_error(described_class::InvalidRefreshToken)
    end

    it "rejects a blank token" do
      expect { described_class.call(raw_token: nil) }
        .to raise_error(described_class::InvalidRefreshToken)
    end

    it "rejects an expired token without revoking the family" do
      pair = issue_for(user)
      pair.refresh_record.update!(expires_at: 1.day.ago)

      expect { described_class.call(raw_token: pair.refresh_token) }
        .to raise_error(described_class::InvalidRefreshToken)
    end
  end

  it "never stores the raw token" do
    pair = issue_for(user)

    expect(pair.refresh_record.token_digest).not_to eq(pair.refresh_token)
    expect(pair.refresh_record.token_digest).to eq(Digest::SHA256.hexdigest(pair.refresh_token))
    expect(RefreshToken.column_names).not_to include("token")
  end
end
