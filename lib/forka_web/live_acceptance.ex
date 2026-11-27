defmodule ForkaWeb.LiveAcceptance do
  @moduledoc false
  # E2E tests only (`config :forka, sql_sandbox: true`): lets a LiveView use the
  # test's database sandbox. PhoenixTestPlaywright sends the sandbox metadata in
  # the browser's User-Agent; every live_session runs this hook before auth hooks.
  # Without the flag it does nothing, so router on_mount lists stay literal.
  if Application.compile_env(:forka, :sql_sandbox) do
    import Phoenix.Component
    import Phoenix.LiveView

    alias Ecto.Adapters.SQL.Sandbox, as: EctoSandbox
    alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox

    def on_mount(:default, _params, _session, socket) do
      socket =
        assign_new(socket, :phoenix_ecto_sandbox, fn ->
          if connected?(socket), do: get_connect_info(socket, :user_agent)
        end)

      PhoenixSandbox.allow(socket.assigns.phoenix_ecto_sandbox, EctoSandbox)

      {:cont, socket}
    end
  else
    def on_mount(:default, _params, _session, socket), do: {:cont, socket}
  end
end
