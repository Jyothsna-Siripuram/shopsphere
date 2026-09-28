# Loaded for every spec run via `.rspec`, including specs that never boot Rails.
# Keep it dependency-free so a single-file run stays fast; Rails-dependent setup
# belongs in spec/rails_helper.rb.
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    # Fails a spec that stubs a method the real object does not define, so a
    # renamed method cannot leave a green but meaningless test behind.
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # `fit`/`fdescribe` narrow a local run; harmless in CI because nothing is tagged.
  config.filter_run_when_matching :focus

  # Enables `--only-failures` and `--next-failure` between runs.
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Requires `RSpec.describe` over bare `describe`, keeping the global namespace clean.
  config.disable_monkey_patching!

  config.default_formatter = "doc" if config.files_to_run.one?

  # Performance is an explicit project goal, so surface slow specs continuously
  # rather than discovering a two-minute suite later.
  config.profile_examples = 10

  # Random order surfaces order dependencies; the seed makes a failure reproducible
  # via `--seed <n>`.
  config.order = :random
  Kernel.srand config.seed
end
