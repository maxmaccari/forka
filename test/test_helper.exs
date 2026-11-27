ExUnit.start(exclude: [:e2e])
Ecto.Adapters.SQL.Sandbox.mode(Forka.Repo, :manual)
{:ok, _} = Application.ensure_all_started(:ex_machina)

# E2E tests need Node and Chromium (assets/node_modules), so the Playwright
# driver starts only when they run: `mix test.e2e`.
if :e2e in ExUnit.configuration()[:include] do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  {:ok, {_ip, port}} = ForkaWeb.Endpoint.server_info(:http)
  Application.put_env(:phoenix_test, :base_url, "http://localhost:#{port}")
end
