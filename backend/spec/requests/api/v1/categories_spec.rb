require "rails_helper"

RSpec.describe "Categories", type: :request do
  describe "GET /api/v1/categories" do
    it "is readable without an account, in navigation order" do
      second = create(:category, name: "Bags", position: 2)
      first = create(:category, name: "Shoes", position: 1)

      get "/api/v1/categories"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |c| c["id"] }).to eq([ first.id, second.id ])
    end

    it "breaks a position tie by name so the menu order is stable" do
      create(:category, name: "Zips", position: 0)
      create(:category, name: "Anoraks", position: 0)

      get "/api/v1/categories"

      expect(response.parsed_body["data"].map { |c| c["name"] }).to eq(%w[Anoraks Zips])
    end

    it "exposes the parent so a client can build the tree" do
      parent = create(:category)
      create(:category, parent:)

      get "/api/v1/categories"

      expect(response.parsed_body["data"].map { |c| c["parent_id"] }).to contain_exactly(nil, parent.id)
    end
  end
end
