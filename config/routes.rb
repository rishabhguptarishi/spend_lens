Rails.application.routes.draw do
  root "home#index"
  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  get "up" => "rails/health#show", as: :rails_health_check

  authenticate :user do
    get "dashboard", to: "dashboard#index", as: :dashboard
    patch "dashboard/layout", to: "dashboard#update_layout", as: :dashboard_layout
    get "upload", to: "statement_uploads#new", as: :new_statement_upload
    post "upload", to: "statement_uploads#create", as: :statement_upload
    get "statements/:id/overlap_review", to: "statement_uploads#overlap_review", as: :statement_overlap_review
    patch "statements/:id/resolve_overlap", to: "statement_uploads#resolve_overlap", as: :statement_resolve_overlap
    resources :bank_accounts do
      resources :statements, only: [:new, :create, :show, :destroy]
    end
    resources :transactions, only: [:index, :update] do
      collection do
        post :bulk_update
      end
    end
    resources :categories
    get "ai", to: "ai#index", as: :ai
    post "ai/ask", to: "ai#ask"
    post "ai/proposals/apply", to: "ai#apply_proposal", as: :ai_apply_proposal
    get "itr/export", to: "itr#export", as: :itr_export
    get "itr", to: "itr#index", as: :itr
    post "itr/documents", to: "itr_tax_documents#create", as: :itr_documents
    delete "itr/documents/:id", to: "itr_tax_documents#destroy", as: :itr_document
    post "itr/documents/:id/extract", to: "itr_tax_documents#extract", as: :itr_document_extract
    get "itr/documents/:id/confirm", to: "itr_tax_documents#confirm", as: :itr_document_confirm
    patch "itr/documents/:id/confirm", to: "itr_tax_documents#confirm"
    get "itr/reconciliation", to: "itr_reconciliation#show", as: :itr_reconciliation
    get "itr/regime", to: "itr#regime", as: :itr_regime
    get "itr/capital_gains", to: "itr#capital_gains", as: :itr_capital_gains
    get "itr/capital_gains/export", to: "itr#capital_gains_export", as: :itr_capital_gains_export
    get "itr/tax_pack", to: "itr#tax_pack", as: :itr_tax_pack
    get "net_worth", to: "net_worth#index", as: :net_worth

    get "investments", to: "investments#index", as: :investments
    get "investments/activity", to: "investments#activity", as: :investments_activity
    get "investments/suggestions", to: "investments#suggestions", as: :investments_suggestions
    post "investments/rescan", to: "investments#rescan", as: :investments_rescan
    get "investments/import", to: "investment_imports#new", as: :new_investment_import
    post "investments/import", to: "investment_imports#create"
    get "investments/import/:id", to: "investment_imports#show", as: :investment_import
    post "investments/import/:id/confirm", to: "investment_imports#confirm", as: :confirm_investment_import
    delete "investments/import/:id", to: "investment_imports#destroy"
    resources :investment_accounts, only: [:new, :create, :edit, :update, :destroy]
    resources :investment_holdings, only: [:new, :create, :edit, :update, :destroy]
    resources :investment_transactions, only: [:new, :create, :edit, :update, :destroy]
    resources :investment_suggestions, only: [] do
      member do
        post :accept
        post :reject
      end
      collection do
        post :accept_all
      end
    end
    get "insights", to: "insights#index", as: :insights
    resources :budgets, only: [:index, :create, :update, :destroy]
    get "settings", to: "settings#index", as: :settings
    patch "settings/preferences", to: "settings#update_preferences", as: :settings_preferences
    patch "settings/notifications", to: "settings#update_notifications", as: :settings_notifications
    resources :investment_detection_rules, only: %i[create destroy], path: "settings/investment_rules"

    get "cards", to: "cards#index", as: :cards
    resources :credit_cards do
      member do
        post :fetch_rewards
      end
      collection do
        get :suggestions
        post :best_for
      end
    end
  end
end
