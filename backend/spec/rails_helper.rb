require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

# Guards against a misconfigured RAILS_ENV pointing the suite at production data.
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Shared matchers, helpers, and (later) factories.
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |file| require file }

# Fails fast when the test database schema is behind db/migrate rather than
# producing confusing errors deep inside an example.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]

  # Lets specs call create/build/build_stubbed directly instead of prefixing
  # every call with FactoryBot.
  config.include FactoryBot::Syntax::Methods

  # Each example runs inside a transaction that is rolled back afterwards.
  #
  # Note for the inventory concurrency specs (Day 11): a spec that exercises real
  # threads on separate connections must opt out of this, because the other
  # connections cannot see data written inside an uncommitted transaction. Those
  # specs will set `use_transactional_tests = false` and clean up explicitly.
  config.use_transactional_fixtures = true

  # Spec type comes from explicit `type:` metadata rather than file location;
  # inferring from location is deprecated in rspec-rails.
  config.filter_rails_from_backtrace!
end
