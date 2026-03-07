Rails.application.routes.draw do
  if Rails.env.development?
    mount Lookbook::Engine, at: "/rails/lookbook"
  end

  root "chats#index"
  get "chat", to: "chats#index", as: :chat

  scope "chat" do
    get  "agents/:agent_name",          to: "chats#show",           as: :agent_chat
    post "agents/:agent_name/messages", to: "chats#create_message", as: :agent_messages
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
