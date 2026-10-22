module Api
  module V1
    module Admin
      class ProductsController < BaseController
        before_action :set_product, only: %i[show update destroy]

        def index
          authorize Product, :index?

          # The status filter narrows the relation BEFORE the query object sees
          # it. Applied afterwards, the search's fuzzy-fallback decision would
          # be made against products the administrator has filtered out.
          relation = policy_scope(Product)
          relation = relation.where(status: params[:status]) if Product::STATUSES.include?(params[:status])

          query = ProductSearchQuery.new(relation: relation, params: filter_params)
          scope = query.call

          pagination = Pagination.new(page: params[:page], per_page: params[:per_page])
          total_count = scope.count
          products = pagination.apply(scope.with_listing_associations)

          render json: {
            data: products.map { |product| ProductSerializer.admin(product) },
            meta: pagination.metadata(total_count).merge(search: query.search_metadata).compact
          }
        end

        def show
          render json: { data: ProductSerializer.admin(@product) }
        end

        def create
          product = Product.new(product_params)
          authorize product

          # One transaction so a product cannot exist without the inventory row
          # checkout depends on. A product with no inventory is not
          # purchasable (Product#purchasable?), so a partial write would create
          # a silently unsellable product rather than a loud failure.
          Product.transaction do
            product.save!
            product.create_inventory!(inventory_params)
          end

          render json: { data: ProductSerializer.admin(product.reload) }, status: :created
        rescue ActiveRecord::RecordInvalid => error
          render_validation_failure(error.record)
        end

        def update
          @product.update!(product_params)
          render json: { data: ProductSerializer.admin(@product.reload) }
        rescue ActiveRecord::RecordInvalid => error
          render_validation_failure(error.record)
        end

        # Archive, not delete. order_items reference products with
        # ON DELETE RESTRICT, so destroying a sold product would either fail or
        # orphan purchase history; ProductPolicy#destroy? is false for everyone.
        def destroy
          @product.update!(status: "archived")

          render json: { data: ProductSerializer.admin(@product) }
        end

        private

        def set_product
          # By id, not slug: an administrator renaming a product must not
          # change the URL they are editing it at.
          @product = policy_scope(Product).with_listing_associations.find(params[:id])
          authorize @product, policy_query
        end

        # DELETE archives, so it is authorized as an update. Asking Pundit the
        # default `destroy?` would always refuse — ProductPolicy#destroy? is
        # false for everyone — and the endpoint would be a permanent 403.
        def policy_query
          action_name == "destroy" ? :update? : "#{action_name}?"
        end

        def product_params
          params.expect(
            product: %i[name slug sku description category_id price compare_at_price
                        status weight_grams published_at]
          )
        end

        def inventory_params
          permitted = params.fetch(:product, {}).permit(:available_quantity, :reorder_threshold)

          { available_quantity: permitted[:available_quantity] || 0,
            reorder_threshold: permitted[:reorder_threshold] || 0 }
        end

        def filter_params
          params.permit(:q, :category, :min_price, :max_price, :in_stock, :sort)
        end

        def render_validation_failure(record)
          render_error(
            code: "validation_failed",
            message: "The product could not be saved",
            status: :unprocessable_content,
            details: record.errors.to_hash(true)
          )
        end
      end
    end
  end
end
