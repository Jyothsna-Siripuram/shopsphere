FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "Category #{n}" }
    sequence(:slug) { |n| "category-#{n}" }
    position { 0 }
  end

  factory :product do
    category
    sequence(:name) { |n| "Product #{n}" }
    sequence(:slug) { |n| "product-#{n}" }
    sequence(:sku) { |n| "SKU-#{n}" }
    price { "49.99" }
    status { "active" }
    published_at { Time.current }

    trait :draft do
      status { "draft" }
      published_at { nil }
    end

    trait :archived do
      status { "archived" }
    end

    # Stock is a separate aggregate, so it is opt-in rather than implicit:
    # a spec that does not care about inventory should not silently create it.
    trait :in_stock do
      transient { quantity { 10 } }
      after(:create) { |product, evaluator| create(:inventory, product:, available_quantity: evaluator.quantity) }
    end

    trait :out_of_stock do
      after(:create) { |product| create(:inventory, product:, available_quantity: 0) }
    end
  end

  factory :product_image do
    product
    sequence(:storage_key) { |n| "products/image-#{n}.jpg" }
    position { 0 }
    is_primary { false }

    trait :primary do
      is_primary { true }
    end
  end

  factory :inventory do
    product
    available_quantity { 10 }
    reorder_threshold { 2 }
  end
end
