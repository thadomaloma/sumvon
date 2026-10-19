Rails.application.routes.draw do
  root "dashboard#show"
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]
  resource :settings, only: %i[show update]
  resources :financial_accounts, path: "accounts", only: %i[index show new create edit update] do
    resource :archive, only: %i[create destroy], module: :financial_accounts
  end
  # Declared before `resources :transactions` so these paths aren't read as transaction ids.
  namespace :transactions do
    resource :statement, only: :show
    resource :receipt_scan, only: :create
  end
  resources :transactions
  resource :finance_tools, only: :show
  resources :account_reconciliations, only: :create
  namespace :recurring_transactions do
    resource :run, only: :create
  end
  resources :recurring_transactions, only: %i[create destroy]
  resources :monthly_closes, only: %i[create destroy]
  resource :transaction_import, only: %i[new create]
  resources :budgets
  get "reports/:year/:month", to: "reports#show", as: :monthly_report,
    constraints: { year: /\d{4}/, month: /\d{1,2}/ }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "manifest.webmanifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker.js" => "pwa#service_worker", as: :pwa_service_worker


  namespace :admin do
    root "dashboard#show"
    resources :users, only: %i[index show edit update destroy] do
      scope module: :users do
        resource :admin_role, only: %i[create destroy]
        resource :suspension, only: %i[create destroy]
        resource :sessions, only: :destroy
        resource :password_reset, only: :create
        resource :deletion, only: :new
      end
    end
    resources :audit_events, only: :index
  end
end
