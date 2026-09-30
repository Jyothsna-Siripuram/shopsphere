# Allowed browser origins for the SPA.
#
# An allowlist, never "*": the refresh endpoint relies on credentialed requests,
# and the CORS specification forbids a wildcard origin when credentials are
# included. More importantly, a wildcard would let any site on the internet
# invoke the API with a victim's cookies attached.
Rails.application.config.x.allowed_origins =
  ENV.fetch("ALLOWED_ORIGINS", "http://localhost:5173")
     .split(",")
     .map(&:strip)
     .reject(&:blank?)
     .freeze

# rack-cors is intentionally not in the Gemfile yet.
#
# The frontend arrives on Day 21. Adding a CORS gem now would configure a
# browser-facing security control months before anything exercises it, and an
# untested allowlist tends to be discovered only when it is wrong. The origin
# list above is already used by the refresh endpoint's Origin check, so the
# configuration surface exists and is tested; only the middleware is deferred.
