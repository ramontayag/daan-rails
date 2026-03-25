Rails.application.routes.draw do
  if Rails.env.development?
    mount Lookbook::Engine, at: "/rails/lookbook"
  end

  root "chats#index"
  get "chat", to: "chats#index", as: :chat

  scope "chat", as: "chat" do
    resources :agents, only: [ :show ], param: :name, path: "agents", controller: "chats" do
      resources :threads, only: [ :show, :create ], shallow: true do
        resources :messages, only: [ :create ]
      end
    end
  end

  resources :documents, only: [:show]

  get "up" => "rails/health#show", as: :rails_health_check
end
