module Api
  module V1
    class CategoriesController < ApplicationController
      skip_before_action :authenticate_user!

      # Not paginated, deliberately: a storefront's category list is tens of
      # rows and is rendered whole in navigation, so paginating it would force
      # the client into several requests to draw one menu. If the taxonomy ever
      # grows past a few hundred rows this needs pagination like any other
      # collection.
      def index
        authorize Category, :index?

        categories = policy_scope(Category).ordered

        render json: { data: categories.map { |category| CategorySerializer.call(category) } }
      end
    end
  end
end
