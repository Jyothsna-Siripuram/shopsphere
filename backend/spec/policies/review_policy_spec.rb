require "rails_helper"

RSpec.describe ReviewPolicy do
  subject(:policy) { described_class }

  let(:author) { create(:user) }
  let(:stranger) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:approved) { create(:review, user: author) }
  let(:pending) { create(:review, :pending, user: author) }

  permissions :show? do
    it "shows an approved review to anyone" do
      expect(policy).to permit(nil, approved)
    end

    it "hides a pending review from strangers but not from its author" do
      expect(policy).not_to permit(stranger, pending)
      expect(policy).to permit(author, pending)
      expect(policy).to permit(admin, pending)
    end
  end

  permissions :update? do
    # An administrator moderates customer words; they do not rewrite them.
    it "belongs to the author alone" do
      expect(policy).to permit(author, approved)
      expect(policy).not_to permit(admin, approved)
      expect(policy).not_to permit(stranger, approved)
    end
  end

  permissions :destroy? do
    it "allows the author or an administrator" do
      expect(policy).to permit(author, approved)
      expect(policy).to permit(admin, approved)
      expect(policy).not_to permit(stranger, approved)
    end
  end

  permissions :moderate? do
    it "is an administrator action" do
      expect(policy).to permit(admin, approved)
      expect(policy).not_to permit(author, approved)
    end

    # Otherwise an administrator could publish their own review unreviewed,
    # which makes moderation decorative.
    it "stops an administrator moderating their own review" do
      own_review = create(:review, :pending, user: admin)

      expect(policy).not_to permit(admin, own_review)
    end
  end

  describe "Scope" do
    it "shows the public only approved reviews" do
      approved
      pending

      expect(described_class::Scope.new(nil, Review.all).resolve).to contain_exactly(approved)
    end

    # So submitting a review does not look like it silently failed.
    it "additionally shows authors their own pending review" do
      approved
      pending

      expect(described_class::Scope.new(author, Review.all).resolve)
        .to contain_exactly(approved, pending)
    end

    it "does not show one customer another customer's pending review" do
      pending

      expect(described_class::Scope.new(stranger, Review.all).resolve).to be_empty
    end
  end
end
