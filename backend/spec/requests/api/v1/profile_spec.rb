require "rails_helper"

RSpec.describe "Profile", type: :request do
  let(:customer) { create(:user) }

  describe "GET /api/v1/profile" do
    it "returns the acting user" do
      get "/api/v1/profile", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "id")).to eq(customer.id)
    end

    it "requires authentication" do
      get "/api/v1/profile"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/profile" do
    it "updates the permitted fields" do
      patch "/api/v1/profile",
            params: { user: { first_name: "Grace", last_name: "Hopper" } },
            headers: auth_headers_for(customer)

      expect(response).to have_http_status(:ok)
      expect(customer.reload.first_name).to eq("Grace")
    end

    # The permitted list comes from UserPolicy#permitted_attributes, which
    # withholds role from a customer editing themselves. Hardcoding the list in
    # the controller would let it drift away from the rule that justifies it.
    it "ignores a self-promotion attempt" do
      patch "/api/v1/profile",
            params: { user: { first_name: "Grace", role: "admin" } },
            headers: auth_headers_for(customer)

      expect(response).to have_http_status(:ok)
      expect(customer.reload).not_to be_admin
    end

    it "ignores a self-unsuspension attempt" do
      patch "/api/v1/profile",
            params: { user: { first_name: "Grace", status: "active" } },
            headers: auth_headers_for(customer)

      expect(customer.reload.first_name).to eq("Grace")
    end

    it "returns field errors for an invalid email" do
      patch "/api/v1/profile",
            params: { user: { email: "not-an-email" } },
            headers: auth_headers_for(customer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details")).to have_key("email")
    end
  end
end
