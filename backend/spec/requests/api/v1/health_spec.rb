require "rails_helper"

RSpec.describe "GET /api/v1/health", type: :request do
  subject(:request_health) { get "/api/v1/health" }

  before do
    allow(Health::ReadinessCheck).to receive(:call)
  end

  it "returns a successful readiness response" do
    request_health

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq({ "data" => { "status" => "ok" } })
  end

  it "does not expose dependency details when a dependency is unavailable" do
    allow(Health::ReadinessCheck).to receive(:call).and_raise(Health::ReadinessCheck::Unavailable)

    request_health

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq(
      {
        "error" => {
          "code" => "service_unavailable",
          "message" => "Service temporarily unavailable"
        }
      }
    )
  end
end
