FactoryBot.define do
  factory :coupon do
    sequence(:code) { |n| "SAVE#{n}" }
    discount_type { "percentage" }
    discount_value { "10.0" }
    minimum_order_amount { "0.0" }
    active { true }

    trait :fixed_amount do
      discount_type { "fixed_amount" }
      discount_value { "5.0" }
    end

    trait :expired do
      starts_at { 2.weeks.ago }
      expires_at { 1.week.ago }
    end

    trait :exhausted do
      usage_limit { 1 }
      times_used { 1 }
    end
  end

  factory :order do
    user
    sequence(:number) { |n| "SS-#{n.to_s.rjust(6, '0')}" }
    sequence(:idempotency_key) { |n| "checkout-key-#{n}" }
    status { "pending" }
    subtotal_amount { "100.00" }
    discount_amount { "0.00" }
    tax_amount { "0.00" }
    shipping_amount { "0.00" }
    # Kept consistent with the components by default so the CHECK constraint is
    # satisfied; specs that exercise the constraint override these explicitly.
    total_amount { "100.00" }
    currency { "USD" }
    shipping_address { { "line1" => "1 Marylebone Road", "city" => "London", "country_code" => "GB" } }

    trait :paid do
      status { "paid" }
      placed_at { Time.current }
    end

    trait :shipped do
      status { "shipped" }
      placed_at { 2.days.ago }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { Time.current }
      cancellation_reason { "Customer changed their mind" }
    end
  end

  factory :order_item do
    order
    product
    product_name { "Product" }
    product_sku { "SKU-1" }
    unit_price { "50.00" }
    quantity { 2 }
    total_price { "100.00" }
  end

  factory :payment do
    order
    sequence(:idempotency_key) { |n| "payment-key-#{n}" }
    amount { "100.00" }
    currency { "USD" }
    status { "pending" }
    provider { "mock" }

    trait :captured do
      status { "captured" }
      sequence(:provider_reference) { |n| "mock-ref-#{n}" }
      processed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failure_reason { "card_declined" }
      processed_at { Time.current }
    end
  end

  factory :review do
    user
    product
    rating { 5 }
    title { "Excellent" }
    body { "Exactly as described." }
    status { "approved" }

    trait :pending do
      status { "pending" }
    end
  end
end
