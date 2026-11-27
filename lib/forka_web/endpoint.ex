defmodule ForkaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :forka

  # E2E tests only: browser requests join the test's database sandbox.
  if Application.compile_env(:forka, :sql_sandbox) do
    alias Phoenix.Ecto.SQL.Sandbox
    plug Sandbox
  end

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_forka_key",
    signing_salt: "+MDt+5Hm",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:user_agent, session: @session_options]],
    longpoll: [connect_info: [:user_agent, session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :forka,
    gzip: false,
    only: ForkaWeb.static_paths()

  if Mix.env() == :dev do
    plug :tidewave_mcp

    defp tidewave_mcp(%{path_info: ["tidewave" | _]} = conn, _opts) do
      Tidewave.call(conn, Tidewave.init(toolbar: false))
    end

    defp tidewave_mcp(conn, _opts), do: conn
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :forka
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ForkaWeb.Router
end
