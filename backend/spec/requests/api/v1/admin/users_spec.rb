require "rails_helper"

RSpec.describe "Admin users", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }

  describe "GET /api/v1/admin/users" do
    it "lists every user for an administrator" do
      admin
      customer

      get "/api/v1/admin/users", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].size).to eq(2)
    end

    # React route guards are a usability feature; this is the real control.
    it "refuses a customer with 403" do
      get "/api/v1/admin/users", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end

    it "refuses an unauthenticated caller with 401" do
      get "/api/v1/admin/users"

      expect(response).to have_http_status(:unauthorized)
    end

    it "never exposes password material" do
      customer

      get "/api/v1/admin/users", headers: auth_headers_for(admin)

      expect(response.body).not_to include("password_digest")
    end
  end

  describe "PATCH /api/v1/admin/users/:id" do
    it "lets an administrator promote another user" do
      patch "/api/v1/admin/users/#{customer.id}",
            params: { user: { role: "admin" } },
            headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(customer.reload).to be_admin
    end

    it "lets an administrator suspend another user" do
      patch "/api/v1/admin/users/#{customer.id}",
            params: { user: { status: "suspended" } },
            headers: auth_headers_for(admin)

      expect(customer.reload.status).to eq("suspended")
    end

    # Without this, the last remaining administrator could lock everyone out of
    # the admin surface with a single request and no way back.
    it "stops an administrator demoting themselves" do
      patch "/api/v1/admin/users/#{admin.id}",
            params: { user: { role: "customer" } },
            headers: auth_headers_for(admin)

      expect(response).to have_http_status(:forbidden)
      expect(admin.reload).to be_admin
    end

    it "stops an administrator suspending themselves" do
      patch "/api/v1/admin/users/#{admin.id}",
            params: { user: { status: "suspended" } },
            headers: auth_headers_for(admin)

      expect(response).to have_http_status(:forbidden)
      expect(admin.reload.status).to eq("active")
    end

    # A no-op submission is not a role change, so it must not trip the
    # self-demotion guard.
    it "allows an administrator to edit their own name" do
      patch "/api/v1/admin/users/#{admin.id}",
            params: { user: { first_name: "Grace", role: "admin" } },
            headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(admin.reload.first_name).to eq("Grace")
    end
  end
end
