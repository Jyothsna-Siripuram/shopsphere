require "rails_helper"

# A factory that drifts out of sync with its model fails here once, rather than
# producing a confusing failure in every spec that happens to use it.
#
# Linting traits as well as base factories matters: a trait is exactly where an
# invalid combination hides, because nothing else exercises it until a spec
# reaches for it months later.
RSpec.describe "Factories" do
  it "produce valid records for every factory and trait" do
    expect { FactoryBot.lint(traits: true) }.not_to raise_error
  end
end
