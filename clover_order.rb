class CloverOrder < ApplicationRecord
  acts_as_tenant(:property)

  belongs_to :payer, class_name: 'GolferBase'

  with_options(dependent: :destroy) do
    has_many :slots
  end

  validates :identifier, presence: true, uniqueness: { scope: :property_id }
  validates :amount, presence: true
  validates :status, presence: true
end
