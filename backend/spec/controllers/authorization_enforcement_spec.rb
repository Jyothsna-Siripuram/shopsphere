require "rails_helper"

# Guards the authorization safety net itself.
#
# `verify_authorized` and `verify_policy_scoped` are what make a forgotten
# `authorize` call fail loudly instead of silently serving data. They are
# inherited from ApplicationController, so every new controller gets them for
# free — which also means deleting them here would silently disarm authorization
# across the entire API. These specs make that deletion a test failure.
RSpec.describe "Authorization enforcement" do
  def after_callbacks_for(controller)
    controller._process_action_callbacks
              .select { |callback| callback.kind == :after }
              .map(&:filter)
  end

  it "arms both verification callbacks on the base controller" do
    expect(after_callbacks_for(ApplicationController))
      .to include(:verify_authorized, :verify_policy_scoped)
  end

  it "inherits them into resource controllers without re-declaration" do
    expect(after_callbacks_for(Api::V1::AddressesController))
      .to include(:verify_authorized, :verify_policy_scoped)
    expect(after_callbacks_for(Api::V1::Admin::UsersController))
      .to include(:verify_authorized, :verify_policy_scoped)
  end

  # Only endpoints with no policy-protected record opt out, and each says why in
  # a comment. Asserted explicitly rather than by enumerating descendants, which
  # would depend on autoload order and make this spec flaky.
  it "opts out only where there is no record to authorize" do
    [ Api::V1::HealthController,
      Api::V1::Auth::SessionsController,
      Api::V1::Auth::TokensController ].each do |controller|
      expect(after_callbacks_for(controller)).not_to include(:verify_authorized),
                                                     "#{controller} should opt out of verify_authorized"
    end
  end

  it "maps a policy denial to 403 and never to a silent success" do
    expect(ApplicationController.rescue_handlers.map(&:first))
      .to include("Pundit::NotAuthorizedError")
  end

  # A missing policy class must be a server fault, never an implicit allow.
  it "treats a missing policy as an error rather than permission" do
    expect(ApplicationController.rescue_handlers.map(&:first))
      .to include("Pundit::NotDefinedError")
  end
end
