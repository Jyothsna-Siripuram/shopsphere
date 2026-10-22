# Product search (ADR-012). The choice of indexes follows the measurements in
# script/benchmarks/product_search.rb, recorded in docs/PERFORMANCE.md §5.
#
# Locking: adding a STORED generated column rewrites the table under an
# ACCESS EXCLUSIVE lock, and a non-concurrent index build blocks writes. Both
# are acceptable here because the table holds no production data yet. Against
# a live catalogue this would be split: add the column in one deploy, then
# build the indexes with `algorithm: :concurrently` and disable_ddl_transaction!
# in another.
class AddSearchToProducts < ActiveRecord::Migration[8.1]
  def change
    # Trusted since PostgreSQL 13, so a non-superuser owner can enable it on
    # RDS without rds_superuser.
    enable_extension "pg_trgm"

    # GENERATED ... STORED rather than a trigger or an Active Record callback.
    #
    # A callback is bypassed by update_all, insert_all and raw SQL, and the
    # index silently drifts from the data. The database computing the column
    # cannot drift. STORED rather than computed at query time because
    # to_tsvector over every description, on every search, is the cost the
    # index exists to avoid.
    #
    # Weights: a term in the name (A) outranks the same term in the
    # description (B), so a product NAMED "boot" sorts above one that merely
    # mentions boots.
    #
    # The two-argument to_tsvector(regconfig, text) is used deliberately: it is
    # IMMUTABLE, which a generated column requires. The one-argument form reads
    # default_text_search_config at runtime and is rejected.
    add_column :products, :search_vector, :virtual,
               type: :tsvector, stored: true,
               as: <<~SQL.squish
                 setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                 setweight(to_tsvector('english', coalesce(description, '')), 'B')
               SQL

    add_index :products, :search_vector, using: :gin

    # Typo fallback only, on the name only. A trigram index over descriptions
    # measured 2.9x the size (41 MB vs 14 MB at 100k products) and still
    # sequential-scanned for common terms, so it bought nothing.
    add_index :products, :name, using: :gin, opclass: :gin_trgm_ops,
                                name: "index_products_on_name_trgm"
  end
end
