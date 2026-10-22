require "rails_helper"

RSpec.describe MoneyFormat do
  it "always renders exactly two decimal places" do
    expect(described_class.call(BigDecimal("50"))).to eq("50.00")
    expect(described_class.call(BigDecimal("50.5"))).to eq("50.50")
    expect(described_class.call(BigDecimal("49.99"))).to eq("49.99")
    expect(described_class.call(BigDecimal("0"))).to eq("0.00")
  end

  # The largest value numeric(12,2) holds. A Float has ~15.9 significant
  # digits, so this survives either way — the point is that it never becomes
  # one, which keeps the guarantee independent of magnitude.
  it "does not lose precision at the top of the column's range" do
    expect(described_class.call(BigDecimal("9999999999.99"))).to eq("9999999999.99")
  end

  it "never uses scientific notation" do
    expect(described_class.call(BigDecimal("1E+3"))).to eq("1000.00")
  end

  it "passes nil through for an optional amount" do
    expect(described_class.call(nil)).to be_nil
  end
end
