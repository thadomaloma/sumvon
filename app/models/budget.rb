class Budget < ApplicationRecord
  include MoneyAttribute

  belongs_to :user
  has_many :budget_categories, dependent: :destroy, inverse_of: :budget
  has_many :categories, through: :budget_categories

  accepts_nested_attributes_for :budget_categories, allow_destroy: true,
    reject_if: ->(attributes) { attributes["planned_amount_minor"].blank? || attributes["planned_amount_minor"].to_i <= 0 }

  money_attribute :planned_amount
  before_validation :apply_requested_reporting_month, :apply_allocations

  # Raw "category id => decimal amount" form input, kept so a rejected form re-renders it.
  attr_reader :allocations

  validates :year, inclusion: { in: 2000..2200 }
  validates :month, inclusion: { in: 1..12 }
  validates :currency, inclusion: { in: MoneyAmount::CURRENCIES }
  validates :planned_amount_minor, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, uniqueness: { scope: [ :user_id, :year, :month ], message: "already has a budget for this month" }
  validate :allocations_do_not_exceed_total
  validate :requested_inputs_are_valid

  scope :chronological, -> { order(year: :desc, month: :desc, currency: :asc) }
  scope :for_period, ->(date) { where(year: date.year, month: date.month) }

  def reporting_month
    Date.new(year, month, 1) if year && month
  rescue Date::Error
    nil
  end

  # Accepts the "YYYY-MM" month picker value; it wins over separately submitted year/month.
  def reporting_month=(value)
    @requested_reporting_month = value
  end

  def allocations=(values)
    @allocations = values.to_h.stringify_keys
  end

  # Expense categories the owner can plan against, plus any already planned that have
  # since been deactivated, so existing allocations stay visible and editable.
  def allocatable_categories
    ids = user.available_categories(:expense).pluck(:id)
    ids |= budget_categories.map(&:category_id)
    Category.where(id: ids).ordered
  end

  def copy_plan_from(source)
    self.currency = source.currency
    self.planned_amount_minor = source.planned_amount_minor
    source.budget_categories.each do |allocation|
      budget_categories.build(category_id: allocation.category_id, planned_amount_minor: allocation.planned_amount_minor)
    end
  end

  def previous_month
    reporting_month.prev_month
  end

  def allocated_amount_minor
    budget_categories.reject(&:marked_for_destruction?).sum(&:planned_amount_minor)
  end

  def unallocated_amount_minor
    planned_amount_minor - allocated_amount_minor
  end

  def rollover_amount_minor
    return 0 unless rollover_enabled?
    previous = user.budgets.find_by(year: previous_month.year, month: previous_month.month, currency:)
    return 0 unless previous
    [ BudgetSummary.new(previous, include_rollover: false).remaining_amount_minor, 0 ].max
  end

  def effective_planned_amount_minor = planned_amount_minor + rollover_amount_minor

  private
    def apply_requested_reporting_month
      return if @requested_reporting_month.blank?

      date = Date.strptime(@requested_reporting_month.to_s, "%Y-%m")
      self.year, self.month = date.year, date.month
      @invalid_reporting_month = false
    rescue Date::Error
      @invalid_reporting_month = true
    end

    def apply_allocations
      return if allocations.nil?

      @invalid_allocations = []
      allocatable_categories.each do |category|
        raw_amount = allocations[category.id.to_s]
        amount = MoneyAmount.to_minor(raw_amount, currency)
        existing = budget_categories.detect { |allocation| allocation.category_id == category.id }

        if raw_amount.present? && amount.nil?
          @invalid_allocations << category
        elsif amount.to_i.positive?
          (existing || budget_categories.build(category:)).planned_amount_minor = amount
        elsif existing
          existing.mark_for_destruction
        end
      end
    end

    def requested_inputs_are_valid
      errors.add(:reporting_month, :invalid) if @invalid_reporting_month
      Array(@invalid_allocations).each do |category|
        errors.add(:base, :invalid_allocation, category: category.name)
      end
    end

    def allocations_do_not_exceed_total
      return if planned_amount_minor.blank?
      errors.add(:budget_categories, "cannot exceed the total budget") if allocated_amount_minor > planned_amount_minor
    end
end
