defmodule ForkaWeb.TidewaveTest do
  use ForkaWeb.ConnCase, async: true

  test "AC-01: tidewave is declared as a dev-only dependency and not loaded in test" do
    deps = Mix.Project.config()[:deps]

    assert {:tidewave, "~> 0.6", only: :dev} in deps
    refute Code.ensure_loaded?(Tidewave)
  end

  test "AC-02: endpoint mounts plug Tidewave with toolbar disabled in dev only, before code_reloading?" do
    source =
      "../../lib/forka_web/endpoint.ex"
      |> Path.expand(__DIR__)
      |> File.read!()

    tidewave_block =
      ~r/if Mix\.env\(\) == :dev do\s+plug Tidewave, toolbar: false\s+end/

    assert [{tidewave_idx, _}] = Regex.run(tidewave_block, source, return: :index)
    assert [{reload_idx, _}] = Regex.run(~r/if code_reloading\? do/, source, return: :index)
    assert tidewave_idx < reload_idx
  end

  test "AC-03: tidewave endpoint is unreachable in test and CSP stays strict", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/tidewave/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "initialize"}))

    assert conn.status == 404

    home_conn = get(build_conn(), ~p"/")
    nonce = home_conn.assigns.csp_nonce
    assert [policy] = get_resp_header(home_conn, "content-security-policy")
    assert policy =~ "script-src 'self' 'nonce-#{nonce}'"
    refute policy =~ "script-src 'self' 'unsafe-inline'"
    refute policy =~ "'unsafe-eval'"
    assert policy =~ "frame-ancestors 'self'"
  end

  test "AC-04: agent MCP configs register tidewave on the default dev URL" do
    mcp_json =
      "../../.mcp.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode!()

    assert mcp_json == %{
             "mcpServers" => %{
               "tidewave" => %{
                 "type" => "http",
                 "url" => "http://localhost:4000/tidewave/mcp"
               }
             }
           }

    opencode_json =
      "../../opencode.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode!()

    assert opencode_json["mcp"] == %{
             "tidewave" => %{
               "type" => "remote",
               "url" => "http://localhost:4000/tidewave/mcp",
               "enabled" => true
             }
           }

    assert opencode_json["instructions"] == [".agents/rules/*.md"]
  end
end
