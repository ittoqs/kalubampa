Rails.application.routes.draw do
  root "dashboard#index"

  resources :campaigns do
    member do
      post :dispatch
    end
  end

  resources :results, only: [:index, :show]

  require "sidekiq/web"
  Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
    ActiveSupport::SecurityUtils.secure_compare(user, ENV.fetch("ADMIN_USERNAME", "admin")) &
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("ADMIN_PASSWORD") { "" })
  end
  mount Sidekiq::Web => "/sidekiq"
end
