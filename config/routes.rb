Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "evenements/locations", to: "events#locations",     as: :event_locations
  get "evenements/details",   to: "events#details",       as: :event_details
  get "evenements",           to: "events#index",         as: :events

  get "artistes/details",     to: "performers#show",      as: :performer
  get "artistes",             to: "performers#index",     as: :performers

  get "presentateurs/details", to: "presenters#show",    as: :presenter
  get "presentateurs",         to: "presenters#index",   as: :presenters

  get "lieux/details",        to: "venues#show",          as: :venue
  get "lieux",                to: "venues#index",         as: :venues

  root "events#index"
end
