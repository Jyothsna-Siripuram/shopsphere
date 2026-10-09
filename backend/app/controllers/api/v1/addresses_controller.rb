module Api
  module V1
    class AddressesController < ApplicationController
      before_action :set_address, only: %i[show update destroy]

      def index
        # Two distinct questions: `authorize` asks whether this caller may list
        # addresses at all, `policy_scope` decides which rows they see. Scoping
        # alone would turn a forbidden listing into an empty 200.
        authorize Address, :index?
        addresses = policy_scope(Address).order(:kind, :id)

        render json: { data: addresses.map { |address| AddressSerializer.call(address) } }
      end

      def show
        render json: { data: AddressSerializer.call(@address) }
      end

      def create
        address = current_user.addresses.new(address_params)
        authorize address

        if address.save
          render json: { data: AddressSerializer.call(address) }, status: :created
        else
          render_validation_failure(address)
        end
      end

      def update
        if @address.update(address_params)
          render json: { data: AddressSerializer.call(@address) }
        else
          render_validation_failure(@address)
        end
      end

      def destroy
        @address.destroy!
        head :no_content
      end

      private

      # Looked up through policy_scope, not Address.find.
      #
      # This is what makes another customer's address return 404 rather than
      # 403: the record is simply not in scope, so `find` raises RecordNotFound.
      # A 403 would confirm the address exists and let an attacker enumerate
      # other customers' address IDs.
      def set_address
        @address = policy_scope(Address).find(params[:id])
        authorize @address
      end

      def address_params
        params.expect(
          address: %i[kind recipient_name line1 line2 city region postal_code
                      country_code phone is_default]
        )
      end

      def render_validation_failure(address)
        render_error(
          code: "validation_failed",
          message: "The address could not be saved",
          status: :unprocessable_content,
          details: address.errors.to_hash(true)
        )
      end
    end
  end
end
