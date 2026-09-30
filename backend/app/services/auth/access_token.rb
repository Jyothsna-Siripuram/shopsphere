module Auth
  # Encodes and decodes short-lived access tokens.
  #
  # Deliberately carries only identity claims. Role is NOT a claim: authorization
  # must read current state, or a demoted administrator would keep their rights
  # until the token expired. The user is loaded for Pundit on every request
  # anyway, so the lookup is a primary-key hit already being paid for.
  class AccessToken
    # Short enough that a leaked access token has a small blast radius, long
    # enough that refreshes are not constant. The refresh token, not this one,
    # provides session longevity.
    LIFETIME = 15.minutes

    # HS256 is correct while one service both signs and verifies. RS256 becomes
    # necessary only when a separate verifier must be unable to mint tokens.
    ALGORITHM = "HS256"
    ISSUER = "shopsphere"

    class InvalidToken < StandardError; end

    class << self
      def encode(user, now: Time.current)
        payload = {
          sub: user.id.to_s,
          iss: ISSUER,
          iat: now.to_i,
          exp: (now + LIFETIME).to_i,
          jti: SecureRandom.uuid
        }

        JWT.encode(payload, secret, ALGORITHM)
      end

      # Raises InvalidToken for every failure mode, so a caller cannot
      # accidentally distinguish "expired" from "forged" and leak that to a
      # client.
      def decode(token)
        raise InvalidToken, "missing token" if token.blank?

        payload, = JWT.decode(
          token,
          secret,
          true,
          # Pinning the algorithm is the mitigation for the alg-confusion family
          # of attacks, where a forged token declares alg:"none" or swaps HS256
          # for RS256 to trick the verifier into using a public key as an HMAC
          # secret. Without this, signature verification can be bypassed.
          algorithm: ALGORITHM,
          verify_expiration: true,
          verify_iat: true,
          iss: ISSUER,
          verify_iss: true,
          required_claims: %w[sub exp iat iss]
        )

        payload
      rescue JWT::DecodeError, JWT::ExpiredSignature => error
        raise InvalidToken, error.message
      end

      def subject_id(token)
        decode(token).fetch("sub")
      end

      private

      # Separate from secret_key_base so JWT signing can be rotated
      # independently of cookie and session signing, and so it maps onto a
      # single Secrets Manager entry in production.
      def secret
        Rails.application.config.x.jwt_secret_key
      end
    end
  end
end
