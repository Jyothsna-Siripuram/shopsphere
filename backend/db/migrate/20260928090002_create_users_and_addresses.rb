class CreateUsersAndAddresses < ActiveRecord::Migration[8.1]
  ROLES = %w[customer admin].freeze
  USER_STATUSES = %w[active suspended].freeze
  ADDRESS_KINDS = %w[shipping billing].freeze

  def change
    create_table :users do |t|
      t.citext :email, null: false
      t.string :password_digest, null: false
      t.string :first_name
      t.string :last_name
      t.string :role, null: false, default: "customer"
      t.string :status, null: false, default: "active"
      t.datetime :last_login_at

      t.timestamps

      # Authentication looks up exactly one user by email on every login. Unique
      # rather than plain because two accounts sharing an email is a security
      # problem, not just a data problem: it makes "which account did I just
      # authenticate?" ambiguous. citext makes the guarantee case-insensitive.
      t.index :email, unique: true

      t.check_constraint "role IN (#{quoted(ROLES)})", name: "users_role_check"
      t.check_constraint "status IN (#{quoted(USER_STATUSES)})", name: "users_status_check"

      # Cheap sanity guard only. Real format validation belongs in the model;
      # this exists so a direct SQL insert cannot create a obviously broken row.
      t.check_constraint "email LIKE '%@%'", name: "users_email_format_check"
    end

    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :recipient_name, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :region
      t.string :postal_code, null: false
      # ISO 3166-1 alpha-2. Fixed width because it is a code, not free text.
      t.string :country_code, null: false, limit: 2
      t.string :phone
      # Named is_default rather than `default`, which is a reserved word in
      # PostgreSQL and would need quoting in every hand-written query.
      t.boolean :is_default, null: false, default: false

      t.timestamps

      t.check_constraint "kind IN (#{quoted(ADDRESS_KINDS)})", name: "addresses_kind_check"
      t.check_constraint "country_code ~ '^[A-Z]{2}$'", name: "addresses_country_code_check"

      # Checkout asks "give me this user's default shipping address". A partial
      # unique index makes "at most one default per kind per user" a database
      # guarantee rather than a race between two concurrent profile updates,
      # both of which would otherwise read false and write true.
      #
      # Partial (WHERE "default") keeps the index to only the handful of rows
      # that are actually defaults, so it stays tiny regardless of how many
      # addresses a user accumulates.
      t.index %i[user_id kind], unique: true, where: "is_default",
              name: "index_addresses_on_one_default_per_user_and_kind"
    end
  end

  private

  def quoted(values)
    values.map { |value| "'#{value}'" }.join(", ")
  end
end
