defmodule ForkaWeb.Router do
  use ForkaWeb, :router

  import ForkaWeb.PlayerAuth

  import ForkaWeb.AdminAuth

  import Backpex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ForkaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_player
  end

  pipeline :admin do
    plug Backpex.ThemeSelectorPlug
    plug :fetch_current_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ForkaWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", ForkaWeb do
  #   pipe_through :api
  # end

  ## Player authentication routes

  scope "/", ForkaWeb do
    pipe_through [:browser, :redirect_if_player_is_authenticated]

    live_session :redirect_if_player_is_authenticated,
      on_mount: [{ForkaWeb.PlayerAuth, :redirect_if_player_is_authenticated}] do
      live "/players/register", PlayerRegistrationLive, :new
      live "/players/log_in", PlayerLoginLive, :new
      live "/players/reset_password", PlayerForgotPasswordLive, :new
      live "/players/reset_password/:token", PlayerResetPasswordLive, :edit
    end

    post "/players/log_in", PlayerSessionController, :create
  end

  scope "/", ForkaWeb do
    pipe_through [:browser, :require_authenticated_player]

    live_session :require_authenticated_player,
      on_mount: [{ForkaWeb.PlayerAuth, :ensure_authenticated}] do
      live "/players/settings", PlayerSettingsLive, :edit
      live "/players/settings/confirm_email/:token", PlayerSettingsLive, :confirm_email
    end
  end

  scope "/", ForkaWeb do
    pipe_through [:browser]

    delete "/players/log_out", PlayerSessionController, :delete

    live_session :current_player,
      on_mount: [{ForkaWeb.PlayerAuth, :mount_current_player}] do
      live "/players/confirm/:token", PlayerConfirmationLive, :edit
      live "/players/confirm", PlayerConfirmationInstructionsLive, :new
    end
  end

  ## Admin routes

  scope "/", ForkaWeb do
    pipe_through [:browser, :redirect_if_admin_is_authenticated]

    live_session :redirect_if_admin_is_authenticated,
      on_mount: [{ForkaWeb.AdminAuth, :redirect_if_admin_is_authenticated}] do
      live "/admin/log_in", AdminLoginLive, :new
    end

    post "/admin/log_in", AdminSessionController, :create
  end

  scope "/", ForkaWeb do
    pipe_through [:browser]

    delete "/admin/log_out", AdminSessionController, :delete

    live_session :current_admin,
      on_mount: [{ForkaWeb.AdminAuth, :mount_current_admin}] do
      live "/admin/confirm/:token", AdminConfirmationLive, :edit
      live "/admin/confirm", AdminConfirmationInstructionsLive, :new
    end
  end

  scope "/admin", ForkaWeb.Admin do
    pipe_through [:browser, :admin, :require_authenticated_admin]

    backpex_routes()

    get "/", RedirectController, :redirect_to_categories

    live_session :default,
      on_mount: [Backpex.InitAssigns, {ForkaWeb.AdminAuth, :ensure_authenticated}],
      layout: {ForkaWeb.Layouts, :admin} do
      live_resources "/categories", CategoryLive
      live_resources "/words", WordLive
      live_resources "/admin_users", AdminUsersLive

      live "/settings", AdminSettingsLive, :edit
      live "/settings/confirm_email/:token", AdminSettingsLive, :confirm_email
    end
  end

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
