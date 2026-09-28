class Inventory < ApplicationRecord
  belongs_to :product, inverse_of: :inventory

  # Mirrors CHECK (available_quantity >= 0) so a form gets a readable error.
  # The constraint, not this validation, is what actually guarantees the
  # invariant: see ADR-001.
  validates :available_quantity,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reorder_threshold,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :low_stock, -> { where(arel_table[:available_quantity].lteq(arel_table[:reorder_threshold])) }

  def in_stock?(quantity = 1)
    available_quantity >= quantity
  end

  def low_stock?
    available_quantity <= reorder_threshold
  end

  # Deliberately NOT implemented here.
  #
  # Decrementing stock safely requires a row lock taken in deterministic order
  # across a whole basket, inside the checkout transaction. Exposing a
  # `decrement!` on the model would invite callers to use it outside that
  # transaction, which is precisely the oversell path ADR-001 exists to close.
  # The operation belongs to Inventory::Reserve, arriving on Day 11.
end
