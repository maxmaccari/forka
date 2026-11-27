import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :forka, Forka.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "forka_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# The server runs so e2e tests (`mix test.e2e`) can reach it. Port 0 lets the OS
# pick a free port, so test runs in parallel worktrees never clash; test_helper.exs
# reads the port it got.
config :forka, ForkaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  secret_key_base: "yiZ72KnT5vsdy8R7Nab+r9zSWJrBwT68s7+LakoThEukt7BT3xMiIbChfWF0W/33",
  server: true

config :phoenix_test,
  otp_app: :forka,
  # CI sets PW_TRACE=true and uploads the traces when an e2e test fails.
  playwright: [trace: System.get_env("PW_TRACE") == "true"]

# In test we don't send emails
config :forka, Forka.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# E2E tests: browser requests and LiveViews share the test's database sandbox
# (Phoenix.Ecto.SQL.Sandbox in the endpoint, ForkaWeb.LiveAcceptance in the router).
config :forka, sql_sandbox: true
