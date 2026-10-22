module Api
  module V1
    class ProductsController < ApplicationController
      # The catalogue is public: browsing must not require an account. The
      # policy scope still restricts an anonymous caller to published products,
      # so this is "no authentication", not "no authorization".
      skip_before_action :authenticate_user!

      def index
        authorize Product, :index?

        query = ProductSearchQuery.new(relation: policy_scope(Product), params: filter_params)
        scope = query.call

        pagination = Pagination.new(page: params[:page], per_page: params[:per_page])

        # COUNT runs against the filtered relation BEFORE limit/offset are
        # applied, and on a relation with no eager loading attached — counting
        # a relation that includes associations makes Active Record build a
        # needless join.
        total_count = scope.count

        products = pagination.apply(scope.with_listing_associations)

        render json: {
          data: products.map { |product| ProductSerializer.call(product) },
          meta: pagination.metadata(total_count).merge(search: query.search_metadata).compact
        }
      end

      def show
        # Looked up by slug, and through the policy scope so a draft product is
        # a 404 for the public rather than a 403 — a 403 would confirm that an
        # unreleased product exists at that slug.
        product = policy_scope(Product)
                  .with_listing_associations
                  .find_by!(slug: params[:id].to_s.downcase)
        authorize product

        render json: { data: ProductSerializer.call(product, detail: true) }
      end

      private

      def filter_params
        params.permit(:q, :category, :min_price, :max_price, :in_stock, :sort)
      end
    end
  end
end
