module AuthHelpers
  # Request specs authenticate by minting a real access token rather than
  # stubbing current_user, so the Authorization header parsing and the
  # authenticate_user! filter are exercised on every example.
  def auth_headers_for(user)
    { "Authorization" => "Bearer #{Auth::AccessToken.encode(user)}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
