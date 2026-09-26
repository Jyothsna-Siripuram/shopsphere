# One URL keeps local Docker and production ElastiCache configuration interchangeable.
Rails.application.config.x.redis_url = ENV.fetch("REDIS_URL")
