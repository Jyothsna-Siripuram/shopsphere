module Auth
  # Verifies an email and password.
  #
  # Returns nil for every failure rather than distinguishing "no such account"
  # from "wrong password": telling them apart turns the login form into a user
  # enumeration oracle an attacker can use to build a target list.
  class AuthenticateUser
    def self.call(email:, password:)
      user = User.find_by(email: email.to_s.strip.downcase)

      # Run the hash comparison even when no user matched, so response time does
      # not reveal whether the address exists. bcrypt dominates this request's
      # cost, so skipping it for unknown emails is an observable timing signal.
      if user.nil?
        User.new(password: SecureRandom.hex(16)).authenticate("timing-equaliser")
        return nil
      end

      return nil unless user.authenticate(password)
      # A suspended account authenticates correctly but must not receive tokens.
      return nil unless user.active_status?

      user
    end
  end
end
