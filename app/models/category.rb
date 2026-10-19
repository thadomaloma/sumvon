class Category < ApplicationRecord
  belongs_to :user, optional: true
  has_many :transactions, dependent: :restrict_with_error
  has_many :budget_categories, dependent: :restrict_with_error

  enum :kind, { income: "income", expense: "expense" }, validate: true
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true, length: { maximum: 60 }
  validates :name, uniqueness: { scope: [ :user_id, :kind ], case_sensitive: false }
end
