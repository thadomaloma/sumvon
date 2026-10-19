class User < ApplicationRecord
  SUPPORTED_LOCALES = %w[en].freeze
  has_secure_password

  # Association order matters: `dependent: :destroy` runs as a before_destroy callback in
  # declaration order, and FinancialAccount/Category use restrict_with_error on their own
  # transactions association to protect single-record deletion elsewhere in the app. So
  # transactions must be destroyed before either parent (financial_accounts, categories)
  # is reached, or a full account
  # deletion (see Admin::UsersController#destroy) raises RecordNotDestroyed.
  has_many :transactions, dependent: :destroy
  has_many :account_reconciliations, dependent: :destroy
  has_many :recurring_transactions, dependent: :destroy
  has_many :monthly_closes, dependent: :destroy
  has_many :budgets, dependent: :destroy
  has_many :financial_accounts, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :audit_events_as_actor, class_name: "AuditEvent", foreign_key: :actor_user_id,
    dependent: :nullify, inverse_of: :actor_user
  has_many :audit_events_as_subject, class_name: "AuditEvent", foreign_key: :subject_user_id,
    dependent: :nullify, inverse_of: :subject_user

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  before_validation :use_supported_locale

  validates :display_name, :country_code, :timezone, :default_currency, :locale, presence: true
  validates :display_name, length: { maximum: 80 }
  validates :email_address, presence: true, length: { maximum: 254 },
    format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  validates :country_code, inclusion: { in: CountryCatalog.codes }
  validates :default_currency, inclusion: { in: MoneyAmount::CURRENCIES }
  validates :locale, inclusion: { in: SUPPORTED_LOCALES }
  validate :timezone_is_valid

  def available_categories(kind = nil)
    scope = Category.where(user_id: [ nil, id ]).active
    kind ? scope.where(kind:) : scope
  end

  def closed_month?(date)
    monthly_closes.exists?(year: date.year, month: date.month)
  end

  def env_admin? = AdminAccess.allowed_email?(email_address)
  def admin_access? = admin? || env_admin?
  def suspended? = suspended_at.present?

  # Removing this user's access would leave Sumvon without any active admin.
  def last_active_admin?
    admin_access? && !suspended? && AdminAccess.effective_admin_count <= 1
  end

  # Returns how many signed-in sessions were ended.
  def suspend!
    transaction do
      update!(suspended_at: Time.current)
      revoke_sessions!
    end
  end

  def reactivate! = update!(suspended_at: nil)

  # Returns how many signed-in sessions were ended.
  def revoke_sessions! = sessions.destroy_all.size

  # Where this user's admin access comes from, for admin UI display and to decide whether
  # the database `admin` flag is safe to toggle: :both/:environment sources can't be revoked
  # by editing the database flag alone, since ADMIN_EMAILS keeps granting access regardless.
  def admin_source
    return :both if admin? && env_admin?
    return :database if admin?
    return :environment if env_admin?
    :none
  end

  private
    def use_supported_locale
      self.locale = "en" unless locale.in?(SUPPORTED_LOCALES)
    end

    def timezone_is_valid
      errors.add(:timezone, "is not recognized") unless ActiveSupport::TimeZone[timezone]
    end
end
