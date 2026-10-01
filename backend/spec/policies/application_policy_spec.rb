require "rails_helper"

RSpec.describe ApplicationPolicy do
  let(:user) { build_stubbed(:user) }

  # The single most important property of the authorization layer: a policy that
  # forgets to define an action denies rather than permits.
  it "denies every action by default" do
    policy = described_class.new(user, double)

    expect(policy.index?).to be(false)
    expect(policy.show?).to be(false)
    expect(policy.create?).to be(false)
    expect(policy.new?).to be(false)
    expect(policy.update?).to be(false)
    expect(policy.edit?).to be(false)
    expect(policy.destroy?).to be(false)
  end

  # Returning `scope` from the base Scope would mean any collection whose policy
  # forgets a Scope silently exposes every row.
  it "refuses to resolve a scope that was never implemented" do
    expect { described_class::Scope.new(user, User.all).resolve }
      .to raise_error(NoMethodError, /must implement/)
  end

  describe "#owner?" do
    it "is false for a nil user even when the record has a nil owner" do
      record = build_stubbed(:address, user_id: nil)

      expect(described_class.new(nil, record).send(:owner?)).to be(false)
    end

    it "is false when the record has no user_id concept at all" do
      expect(described_class.new(user, build_stubbed(:category)).send(:owner?)).to be(false)
    end
  end
end
