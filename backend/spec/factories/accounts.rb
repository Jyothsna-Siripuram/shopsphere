FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "customer#{n}@example.com" }
    password { "correct-horse-battery" }
    first_name { "Ada" }
    last_name { "Lovelace" }
    role { "customer" }
    status { "active" }

    trait :admin do
      role { "admin" }
      sequence(:email) { |n| "admin#{n}@example.com" }
    end

    trait :suspended do
      status { "suspended" }
    end
  end

  factory :address do
    user
    kind { "shipping" }
    recipient_name { "Ada Lovelace" }
    line1 { "1 Marylebone Road" }
    city { "London" }
    postal_code { "NW1 5LS" }
    country_code { "GB" }

    trait :billing do
      kind { "billing" }
    end

    trait :default do
      is_default { true }
    end
  end

  factory :cart do
    user
    status { "active" }
  end

  factory :cart_item do
    cart
    product
    quantity { 1 }
  end

  factory :wishlist do
    user
  end

  factory :wishlist_item do
    wishlist
    product
  end
end
