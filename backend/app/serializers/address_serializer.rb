class AddressSerializer
  def self.call(address)
    {
      id: address.id,
      kind: address.kind,
      recipient_name: address.recipient_name,
      line1: address.line1,
      line2: address.line2,
      city: address.city,
      region: address.region,
      postal_code: address.postal_code,
      country_code: address.country_code,
      phone: address.phone,
      is_default: address.is_default,
      created_at: address.created_at.iso8601
    }
  end
end
