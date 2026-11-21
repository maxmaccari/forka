import Config
import Dotenvy

env = config_env()

dotenv_files =
  [".env", ".env.#{env}"] ++
    if(env == :test, do: [], else: [".env.local"]) ++ [".env.#{env}.local"]

source!(dotenv_files ++ [System.get_env()])

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/forka start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if env!("PHX_SERVER", :boolean, false) do
  config :forka, ForkaWeb.Endpoint, server: true
end

if env == :dev do
  worktree =
    try do
      case System.cmd(
             "git",
             ~w(rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel),
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          case String.split(output, "\n", trim: true) do
            [git_dir, common_dir, root] when git_dir != common_dir -> root
            _ -> nil
          end

        _ ->
          nil
      end
    rescue
      ErlangError -> nil
    end

  default_port = if worktree, do: 4100 + :erlang.phash2(worktree, 900), else: 4000
  port = env!("PORT", :integer, default_port)

  config :forka, ForkaWeb.Endpoint, http: [port: port], url: [port: port]

  if worktree do
    config :forka, :worktree, %{name: Path.basename(worktree), port: port}
  end
end

if env == :prod do
  # Example: ecto://USER:PASS@HOST/DATABASE
  database_url = env!("DATABASE_URL", :string!)

  maybe_ipv6 = if env!("ECTO_IPV6", :string, "false") in ~w(true 1), do: [:inet6], else: []

  config :forka, Forka.Repo,
    # ssl: true,
    url: database_url,
    pool_size: env!("POOL_SIZE", :integer, 10),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  # Generate a value with mix phx.gen.secret.
  secret_key_base = env!("SECRET_KEY_BASE", :string!)

  host = env!("PHX_HOST", :string, "example.com")
  port = env!("PORT", :integer, 4000)

  config :forka, :dns_cluster_query, env!("DNS_CLUSTER_QUERY", :string?, nil)

  config :forka, ForkaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :forka, ForkaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: env!("SOME_APP_SSL_KEY_PATH", :string!),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :forka, ForkaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :forka, Forka.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: env!("MAILGUN_API_KEY", :string!),
  #       domain: env!("MAILGUN_DOMAIN", :string!)
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
