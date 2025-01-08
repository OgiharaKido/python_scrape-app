Rails.application.routes.draw do
  resources :articles, only: [ "new", "create" ]
  root "articles#new"
end
