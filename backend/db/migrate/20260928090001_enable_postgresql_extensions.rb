class EnablePostgresqlExtensions < ActiveRecord::Migration[8.1]
  def change
    # Case-insensitive text for identifiers that users type: email addresses,
    # SKUs, coupon codes, order numbers.
    #
    # The alternative is a regular string plus a functional unique index on
    # LOWER(column) and LOWER() wrapped around every lookup. citext pushes that
    # into the type, so a unique index cannot be accidentally bypassed by a
    # query that forgets to downcase. Without it, "User@Example.com" and
    # "user@example.com" become two accounts.
    #
    # Trade-off: comparisons are marginally slower than bytewise text, and the
    # collation rules are locale-dependent. Both are irrelevant at this scale
    # next to the correctness guarantee.
    enable_extension "citext"
  end
end
