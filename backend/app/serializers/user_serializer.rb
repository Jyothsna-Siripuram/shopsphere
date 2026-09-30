# Plain object rather than a serialization gem.
#
# The API returns a small, stable set of shapes, and an explicit allowlist here
# is what guarantees password_digest, refresh token material and internal
# timestamps can never reach a response by accident. A serializer that renders
# "all attributes except..." fails open the moment a column is added.
class UserSerializer
  def self.call(user)
    {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      role: user.role,
      created_at: user.created_at.iso8601
    }
  end
end
