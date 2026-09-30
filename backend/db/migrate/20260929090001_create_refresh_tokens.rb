class CreateRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :refresh_tokens do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }

      # SHA-256 of the raw token, never the token itself. A database disclosure
      # must not hand the attacker usable credentials.
      #
      # SHA-256 rather than bcrypt is deliberate: the raw token is 256 bits of
      # CSPRNG output, so there is no dictionary and no brute-force risk. A slow
      # KDF protects low-entropy human secrets; here it would only add latency
      # to every refresh. Fixed 64-char hex.
      t.string :token_digest, null: false, limit: 64

      # Rotation lineage. Every token issued from the same login shares a family;
      # detecting reuse revokes the whole family rather than one token, because a
      # replayed token means two parties hold it.
      t.uuid :family_id, null: false

      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :revoked_reason

      # Audit context, useful when a customer reports a compromise.
      t.string :user_agent
      t.string :client_ip

      t.timestamps

      # Refresh presents a raw token; we hash it and look it up here. Unique
      # because one digest must identify exactly one token row.
      t.index :token_digest, unique: true

      # Reuse detection revokes an entire family in one statement, and logout
      # revokes every active token for a user. Both filter on these columns.
      t.index %i[family_id revoked_at]
      t.index %i[user_id revoked_at]

      # CleanupExpiredTokensJob (Day 16) deletes rows past expiry. Partial,
      # because only unrevoked rows are worth scanning: revoked ones are already
      # inert and will be removed by the same sweep.
      t.index :expires_at, where: "revoked_at IS NULL",
              name: "index_refresh_tokens_on_active_expiry"

      t.check_constraint "(revoked_at IS NULL) = (revoked_reason IS NULL)",
                         name: "refresh_tokens_revoked_reason_matches_state_check"
      t.check_constraint "token_digest ~ '^[0-9a-f]{64}$'",
                         name: "refresh_tokens_digest_format_check"
    end
  end
end
