defmodule ForkaWeb.ProductionSSLTest do
  use ExUnit.Case, async: true

  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]
  import Plug.Test, only: [conn: 2]

  @host "forka.example"

  setup do
    endpoint = Config.Reader.read!("config/prod.exs", env: :prod)[:forka][ForkaWeb.Endpoint]
    ssl_options = Plug.SSL.init(Keyword.put(endpoint[:force_ssl], :host, @host))
    {:ok, ssl_options: ssl_options}
  end

  test "allows HTTPS forwarded by the proxy and adds HSTS", %{ssl_options: ssl_options} do
    conn =
      conn(:get, "http://#{@host}/")
      |> put_req_header("x-forwarded-proto", "https")
      |> Plug.SSL.call(ssl_options)

    refute conn.halted
    assert conn.scheme == :https
    assert ["max-age=" <> _] = get_resp_header(conn, "strict-transport-security")
  end

  test "redirects plain HTTP to HTTPS", %{ssl_options: ssl_options} do
    conn = Plug.SSL.call(conn(:get, "http://#{@host}/"), ssl_options)

    assert conn.halted
    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["https://#{@host}/"]
  end
end
