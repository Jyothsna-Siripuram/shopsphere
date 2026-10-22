module Carts
  # Raised for a request that is well-formed but cannot be honoured. Carries
  # a stable code for the client and per-field details.
  class InvalidLine < StandardError
    attr_reader :code, :details

    def initialize(message, code:, details: nil)
      super(message)
      @code = code
      @details = details
    end
  end
end
