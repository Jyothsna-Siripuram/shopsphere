require "rails_helper"

RSpec.describe "Addresses", type: :request do
  let(:customer) { create(:user) }
  let(:stranger) { create(:user) }
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/addresses" do
    it "returns only the caller's own addresses" do
      mine = create(:address, user: customer)
      create(:address, user: stranger)

      get "/api/v1/addresses", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].map { |a| a["id"] }).to contain_exactly(mine.id)
    end

    it "requires authentication" do
      get "/api/v1/addresses"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/addresses/:id" do
    # The 403-versus-404 decision in practice. A 403 here would confirm the
    # address exists, letting an attacker enumerate other customers' records.
    it "returns 404, not 403, for another customer's address" do
      other = create(:address, user: stranger)

      get "/api/v1/addresses/#{other.id}", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
      # The response must not reveal anything about the record that exists.
      expect(response.body).not_to include(other.postal_code)
    end

    it "returns the caller's own address" do
      mine = create(:address, user: customer)

      get "/api/v1/addresses/#{mine.id}", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "id")).to eq(mine.id)
    end
  end

  describe "POST /api/v1/addresses" do
    let(:params) do
      { address: { kind: "shipping", recipient_name: "Ada Lovelace",
                   line1: "1 Marylebone Road", city: "London",
                   postal_code: "NW1 5LS", country_code: "GB" } }
    end

    it "creates an address owned by the caller" do
      expect { post "/api/v1/addresses", params: params, headers: auth_headers_for(customer) }
        .to change { customer.addresses.count }.by(1)

      expect(response).to have_http_status(:created)
    end

    # Ownership comes from current_user, never from the request body.
    it "ignores an attempt to create an address for someone else" do
      post "/api/v1/addresses",
           params: params.deep_merge(address: { user_id: stranger.id }),
           headers: auth_headers_for(customer)

      expect(Address.last.user_id).to eq(customer.id)
    end
  end

  describe "PATCH and DELETE" do
    it "refuses to modify another customer's address" do
      other = create(:address, user: stranger)

      patch "/api/v1/addresses/#{other.id}",
            params: { address: { city: "Hijacked" } },
            headers: auth_headers_for(customer)

      expect(response).to have_http_status(:not_found)
      expect(other.reload.city).not_to eq("Hijacked")
    end

    it "refuses to delete another customer's address" do
      other = create(:address, user: stranger)

      expect { delete "/api/v1/addresses/#{other.id}", headers: auth_headers_for(customer) }
        .not_to change(Address, :count)

      expect(response).to have_http_status(:not_found)
    end

    # An administrator can read addresses but has no business editing them;
    # AddressPolicy#update? is owner-only, so this is a 403 rather than a 404.
    it "refuses to let an administrator edit a customer's address" do
      address = create(:address, user: customer)

      patch "/api/v1/addresses/#{address.id}",
            params: { address: { city: "Edited" } },
            headers: auth_headers_for(admin)

      expect(response).to have_http_status(:forbidden)
      expect(address.reload.city).not_to eq("Edited")
    end
  end
end
