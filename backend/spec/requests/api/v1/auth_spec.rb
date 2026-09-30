require "rails_helper"

RSpec.describe "Authentication endpoints", type: :request do
  let(:password) { "correct-horse-battery" }

  def refresh_cookie
    # Rack encodes the Set-Cookie header; read the jar the integration session
    # maintains rather than parsing it by hand.
    cookies[RefreshTokenCookie::COOKIE_NAME.to_s]
  end

  def set_cookie_header
    response.headers["Set-Cookie"].then { |value| value.is_a?(Array) ? value.join("\n") : value.to_s }
  end

  describe "POST /api/v1/auth/register" do
    let(:valid_params) do
      { user: { email: "new@example.com", password: password,
                password_confirmation: password, first_name: "Ada" } }
    end

    it "creates the account and returns an access token" do
      post "/api/v1/auth/register", params: valid_params

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "user", "email")).to eq("new@example.com")
      expect(response.parsed_body.dig("data", "access_token")).to be_present
      expect(response.parsed_body.dig("data", "expires_in")).to eq(900)
    end

    it "never exposes password material" do
      post "/api/v1/auth/register", params: valid_params

      expect(response.body).not_to include(password)
      expect(response.parsed_body["data"]["user"].keys)
        .to contain_exactly("id", "email", "first_name", "last_name", "role", "created_at")
    end

    it "delivers the refresh token only as an HttpOnly cookie, never in the body" do
      post "/api/v1/auth/register", params: valid_params

      raw = RefreshToken.last
      expect(response.body).not_to include(raw.token_digest)
      expect(response.parsed_body["data"]).not_to have_key("refresh_token")
      # Rack 3 emits cookie attributes lowercase, so match case-insensitively
      # rather than asserting a particular casing.
      expect(set_cookie_header).to match(/httponly/i)
      expect(set_cookie_header).to match(/samesite=lax/i)
      expect(set_cookie_header).to match(%r{path=/api/v1/auth}i)
    end

    # Privilege escalation through a crafted request body is the classic
    # mass-assignment failure.
    it "ignores an attempt to self-assign the admin role" do
      post "/api/v1/auth/register",
           params: valid_params.deep_merge(user: { role: "admin" })

      expect(User.find_by(email: "new@example.com")).not_to be_admin
    end

    it "returns field-level errors for an invalid submission" do
      post "/api/v1/auth/register", params: { user: { email: "nope", password: "short" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details")).to include("email", "password")
    end
  end

  describe "POST /api/v1/auth/login" do
    let!(:user) { create(:user, password: password) }

    it "authenticates and records the login" do
      expect { post "/api/v1/auth/login", params: { user: { email: user.email, password: password } } }
        .to change { user.reload.last_login_at }.from(nil)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "access_token")).to be_present
    end

    it "accepts a differently-cased email address" do
      post "/api/v1/auth/login",
           params: { user: { email: user.email.upcase, password: password } }

      expect(response).to have_http_status(:ok)
    end

    # A distinguishable response would turn login into a user-enumeration oracle.
    it "returns an identical error for a wrong password and an unknown account" do
      post "/api/v1/auth/login", params: { user: { email: user.email, password: "wrong" } }
      wrong_password = response.parsed_body

      post "/api/v1/auth/login", params: { user: { email: "ghost@example.com", password: password } }
      unknown_account = response.parsed_body

      expect(wrong_password).to eq(unknown_account)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a suspended account that presents correct credentials" do
      suspended = create(:user, :suspended, password: password)

      post "/api/v1/auth/login", params: { user: { email: suspended.email, password: password } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/auth/refresh" do
    let(:user) { create(:user, password: password) }

    before do
      post "/api/v1/auth/login", params: { user: { email: user.email, password: password } }
    end

    it "exchanges the cookie for a new access token without a request body" do
      original_cookie = refresh_cookie

      post "/api/v1/auth/refresh"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "access_token")).to be_present
      expect(refresh_cookie).not_to eq(original_cookie)
    end

    it "rejects a replayed cookie and clears it" do
      stolen = refresh_cookie
      post "/api/v1/auth/refresh" # legitimate rotation

      cookies[RefreshTokenCookie::COOKIE_NAME.to_s] = stolen
      post "/api/v1/auth/refresh"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_refresh_token")
      # The response must not reveal that reuse specifically was detected.
      expect(response.body).not_to match(/reuse/i)
    end

    it "rejects a request with no cookie at all" do
      cookies.delete(RefreshTokenCookie::COOKIE_NAME.to_s)

      post "/api/v1/auth/refresh"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a request from an origin outside the allowlist" do
      post "/api/v1/auth/refresh", headers: { "Origin" => "https://evil.example.com" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden_origin")
    end

    it "accepts a request from an allowed origin" do
      post "/api/v1/auth/refresh", headers: { "Origin" => "http://localhost:5173" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/auth/logout" do
    let(:user) { create(:user, password: password) }

    before do
      post "/api/v1/auth/login", params: { user: { email: user.email, password: password } }
      @access_token = response.parsed_body.dig("data", "access_token")
    end

    it "revokes the refresh token so the session cannot be resumed" do
      post "/api/v1/auth/logout", headers: { "Authorization" => "Bearer #{@access_token}" }

      expect(response).to have_http_status(:no_content)
      expect(RefreshToken.where(user: user).active).to be_empty

      post "/api/v1/auth/refresh"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires authentication" do
      post "/api/v1/auth/logout"

      expect(response).to have_http_status(:unauthorized)
    end

    # Signing out on one device must not sign the customer out everywhere.
    it "leaves other sessions intact" do
      other_session, = RefreshToken.issue!(user: user)

      post "/api/v1/auth/logout", headers: { "Authorization" => "Bearer #{@access_token}" }

      expect(other_session.reload).to be_active
    end
  end

  describe "authentication enforcement" do
    it "rejects a malformed Authorization header" do
      post "/api/v1/auth/logout", headers: { "Authorization" => "Basic abc123" }

      expect(response).to have_http_status(:unauthorized)
    end

    # The access token stays valid for up to 15 minutes, so suspension must be
    # read from current state on every request rather than trusted from a claim.
    it "stops accepting a valid token once the account is suspended" do
      user = create(:user, password: password)
      token = Auth::AccessToken.encode(user)
      user.update!(status: "suspended")

      post "/api/v1/auth/logout", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
