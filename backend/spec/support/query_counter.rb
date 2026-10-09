# Counts the SQL statements a block issues.
#
# Asserting `association.loaded?` proves eager loading was requested. Counting
# queries proves it actually worked — and, more importantly, that the count does
# not grow with the number of records, which is the definition of an N+1.
module QueryCounter
  IGNORED = /\A(TRANSACTION|SAVEPOINT|RELEASE|ROLLBACK|BEGIN|COMMIT|SHOW|SET|PRAGMA)/i

  def count_queries
    queries = []

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if payload[:sql].match?(IGNORED)

      queries << payload[:sql]
    end

    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
