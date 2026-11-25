defmodule ForkaWeb.Router do
  use ForkaWeb, :router

  import ForkaWeb.PlayerAuth

  import ForkaWeb.AdminAuth

  import Backpex.Router

  # The per-request CSP header is set by the ContentSecurityPolicy plug.
  # sobelow_skip ["Config.CSP"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ForkaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_player
    plug :put_player_locale
    plug :put_current_path
    plug ForkaWeb.Plugs.ContentSecurityPolicy
  end

  pipeline :admin do
    plug :fetch_current_admin
  end

  pipeline :admin_layout do
    plug :put_root_layout, html: {ForkaWeb.Layouts, :admin_root}
    plug :put_admin_locale
  end

  pipeline :api do
    plug :accepts, ["json"]
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
      live "/rooms/new", RoomFormLive, :new
      live "/rooms/:id", RoomLive, :show
      live "/rooms/:id/settings", RoomFormLive, :edit
      live "/players/settings", PlayerSettingsLive, :edit
      live "/players/settings/confirm_email/:token", PlayerSettingsLive, :confirm_email
    end
  end

  scope "/", ForkaWeb do
    pipe_through [:browser]

    delete "/players/log_out", PlayerSessionController, :delete

    live_session :current_player,
      on_mount: [{ForkaWeb.PlayerAuth, :mount_current_player}] do
      live "/", RoomDirectoryLive, :index
      live "/rooms/:id/join", RoomInviteLive, :show
      live "/players/confirm/:token", PlayerConfirmationLive, :edit
      live "/players/confirm", PlayerConfirmationInstructionsLive, :new
    end
  end

  ## Admin routes

  scope "/", ForkaWeb do
    pipe_through [:browser, :admin_layout, :redirect_if_admin_is_authenticated]

    live_session :redirect_if_admin_is_authenticated,
      on_mount: [{ForkaWeb.AdminAuth, :redirect_if_admin_is_authenticated}] do
      live "/admin/log_in", AdminLoginLive, :new
    end

    post "/admin/log_in", AdminSessionController, :create
  end

  scope "/", ForkaWeb do
    pipe_through [:browser, :admin_layout]

    delete "/admin/log_out", AdminSessionController, :delete

    live_session :current_admin,
      on_mount: [{ForkaWeb.AdminAuth, :mount_current_admin}] do
      live "/admin/confirm/:token", AdminConfirmationLive, :edit
      live "/admin/confirm", AdminConfirmationInstructionsLive, :new
    end
  end

  scope "/admin", ForkaWeb.Admin do
    pipe_through [:browser, :admin_layout, :admin, :require_authenticated_admin]

    get "/", RedirectController, :redirect_to_categories

    backpex_routes()

    live_session :default,
      on_mount: [{ForkaWeb.AdminAuth, :ensure_authenticated}, Backpex.InitAssigns] do
      live_resources "/categories", CategoryLive
      live_resources "/words", WordLive
      live_resources "/players", PlayerLive
      live_resources "/admins", AdminLive
      live_resources "/games", GameLive

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

      live_dashboard "/dashboard",
        metrics: ForkaWeb.Telemetry,
        csp_nonce_assign_key: :csp_nonce

      forward "/mailbox", Plug.Swoosh.MailboxPreview,
        csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    end
  end

  defp put_player_locale(conn, _opts) do
    Gettext.put_locale(ForkaWeb.Gettext, "pt_BR")
    conn
  end

  defp put_current_path(conn, _opts), do: assign(conn, :current_path, conn.request_path)

  defp put_admin_locale(conn, _opts) do
    Gettext.put_locale(ForkaWeb.Gettext, "en")
    conn
  end
end
