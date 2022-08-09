class CloverTaxRate
  include ActiveModel::Model
  include ActiveModel::Validations
  include ActiveModel::Attributes

  attribute :id, :string
  attribute :name, :string
  attribute :rate, :decimal

  def self.from_clovery_tax_hash(tax_hash)
    hash = tax_hash.slice(*CloverTaxRate.new.attributes.keys)
    hash["rate"] = tax_hash["rate"] / 100_000.to_f
    CloverTaxRate.new(hash)
  end
end
