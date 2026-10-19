class BudgetCategory < ApplicationRecord
  belongs_to :budget, inverse_of: :budget_categories
  belongs_to :category

  validates :category_id, uniqueness: { scope: :budget_id }
  validates :planned_amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validate :expense_category_belongs_to_budget_user

  private
    def expense_category_belongs_to_budget_user
      return unless category && budget
      errors.add(:category, "must be an expense category") unless category.expense?
      unless category.user_id.nil? || category.user_id == budget.user_id
        errors.add(:category, "is not available")
      end
    end
end
