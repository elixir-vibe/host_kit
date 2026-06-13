defmodule HelloPhoenixWeb.Router do
  use HelloPhoenixWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", HelloPhoenixWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
  end

  scope "/", HelloPhoenixWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end
end
