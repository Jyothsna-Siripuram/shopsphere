module Health
  class ReadinessCheck
    class Unavailable < StandardError; end

    def self.call
      new.call
    end

    def call
      check_database!
      check_redis!
    end

    private

    def check_database!
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.select_value("SELECT 1") == 1 ||
          raise(Unavailable, "database unavailable")
      end
    rescue ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::StatementInvalid,
           PG::Error => error
      raise Unavailable, "database unavailable: #{error.class}"
    end

    def check_redis!
      client = RedisClient.config(
        url: Rails.configuration.x.redis_url
      ).new_client

      client.call("PING") == "PONG" ||
        raise(Unavailable, "redis unavailable")
    rescue RedisClient::Error, SocketError => error
      raise Unavailable, "redis unavailable: #{error.class}"
    ensure
      client&.close
    end
  end
end
