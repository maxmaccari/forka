defmodule ForkaWeb.Router do
  use ForkaWeb, :router

  import Backpex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ForkaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug Backpex.ThemeSelectorPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ForkaWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/admin", ForkaWeb do
    pipe_through [:browser, :admin]

    backpex_routes()

    get "/", RedirectController, :redirect_to_categories

    live_session :default, on_mount: Backpex.InitAssigns do
      live_resources "/categories", CategoryLive
      live_resources "/words", WordLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ForkaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:forka, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ForkaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
