# Fail at boot, not at first login, if the signing key is missing.
#
# Development and test derive a stable key from secret_key_base so a fresh clone
# runs without extra setup. Production demands a real injected secret: deriving
# it there would couple JWT rotation to secret_key_base rotation and would mean
# a missing secret silently produced a working-but-wrong configuration.
Rails.application.config.x.jwt_secret_key =
  if Rails.env.local?
    ENV.fetch("JWT_SECRET_KEY") do
      Rails.application.key_generator.generate_key("shopsphere/jwt", 32)
    end
  else
    ENV.fetch("JWT_SECRET_KEY") do
      raise KeyError, "JWT_SECRET_KEY must be set outside development and test"
    end
  end
