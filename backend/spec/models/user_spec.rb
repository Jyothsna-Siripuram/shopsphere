require "rails_helper"

RSpec.describe User, type: :model do
  describe "password storage" do
    it "never persists the password in readable form" do
      user = create(:user, password: "correct-horse-battery")

      expect(user.password_digest).to be_present
      expect(user.password_digest).not_to include("correct-horse-battery")
      expect(user.authenticate("correct-horse-battery")).to eq(user)
      expect(user.authenticate("wrong")).to be(false)
    end

    it "rejects a password short enough to be guessable" do
      user = build(:user, password: "short")

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    # bcrypt silently truncates input beyond 72 bytes, so accepting a longer
    # password would give a false sense of strength.
    it "rejects a password beyond the length bcrypt actually hashes" do
      expect(build(:user, password: "a" * 73)).not_to be_valid
    end
  end

  describe "email handling" do
    it "normalises to lowercase so the stored form is canonical" do
      user = create(:user, email: "  Ada@Example.COM  ")

      expect(user.email).to eq("ada@example.com")
    end

    it "treats a differently-cased address as the same account" do
      create(:user, email: "ada@example.com")
      duplicate = build(:user, email: "ADA@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
  end

  describe "#admin?" do
    # Every Pundit policy asks this and nothing else, so that ADR-004 stays
    # reversible without touching authorization code.
    it "is true only for the admin role" do
      expect(build(:user, :admin)).to be_admin
      expect(build(:user)).not_to be_admin
    end
  end

  describe "#active_cart" do
    it "returns only the active cart, ignoring converted history" do
      user = create(:user)
      create(:cart, user:, status: "converted")
      active = create(:cart, user:, status: "active")

      expect(user.reload.active_cart).to eq(active)
    end
  end

  it "rejects a role outside the permitted set rather than raising" do
    user = build(:user)
    user.role = "superadmin"

    expect(user).not_to be_valid
    expect(user.errors[:role]).to be_present
  end
end
