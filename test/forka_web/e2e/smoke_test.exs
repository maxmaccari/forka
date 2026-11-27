defmodule ForkaWeb.E2E.SmokeTest do
  # Runs in Chromium (`mix test.e2e`). Checks what LiveViewTest cannot, since
  # LiveViewTest never runs a browser: LiveView connects over WebSocket, the
  # server enforces a nonced CSP, and the nonced inline theme initializer
  # applies a saved theme before the external app bundle runs.
  use ForkaWeb.E2ECase, async: true

  import ExUnit.CaptureLog

  alias PhoenixTest.Playwright.Config
  alias PlaywrightEx.{Connection, Frame, Page, Request, Route, Supervisor}

  test "E2E-01: LiveView connects over WebSocket and the nonced theme initializer runs under CSP",
       %{conn: conn} do
    timeout = Config.global(:timeout)

    log =
      capture_log(fn ->
        conn
        |> visit(~p"/players/log_in")
        |> assert_enforced_nonce_csp(timeout)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_websocket_transport()
        |> click_button("Tema: sistema. Trocar tema")
        |> assert_has("html[data-theme=light]")
        |> assert_has(~s|button[aria-label="Tema: claro. Trocar tema"]|)
        |> assert_inline_theme_initializer_runs_before_app_bundle("light", timeout)
      end)

    refute log =~ "Content Security Policy"
  end

  test "E2E-02: an async browser session joins the SQL sandbox across login and LiveView mount",
       %{conn: conn} do
    player = insert(:player)

    conn
    |> log_in(player)
    |> visit(~p"/players/settings")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Minha conta")
  end

  defp assert_enforced_nonce_csp(conn, timeout) do
    unwrap(conn, fn %{frame_id: frame_id} ->
      {:ok, %{guid: request_id}} = Frame.document_request(frame_id)
      {:ok, %{guid: response_id}} = Request.response(request_id, timeout: timeout)
      response = Connection.initializer!(Supervisor.connection_name(), response_id)

      csp = Enum.find_value(response.headers, &header_value(&1, "content-security-policy"))

      assert is_binary(csp), "expected Content-Security-Policy response header"

      assert csp =~ ~r/(?:^|;\s*)script-src\b[^;]*'nonce-[^']+'/,
             "expected script-src nonce in Content-Security-Policy, got: #{inspect(csp)}"

      refute csp =~ ~r/(?:^|;\s*)script-src\b[^;]*'unsafe-inline'/,
             "expected script-src without 'unsafe-inline' in Content-Security-Policy, got: #{inspect(csp)}"
    end)
  end

  defp assert_websocket_transport(conn) do
    evaluate(
      conn,
      """
      () => {
        const liveSocket = window.liveSocket;
        const transport = liveSocket && liveSocket.socket && liveSocket.socket.conn;
        return {
          connected: Boolean(liveSocket && liveSocket.isConnected()),
          isWebSocket: transport instanceof WebSocket,
          open: Boolean(transport && transport.readyState === WebSocket.OPEN),
          url: (transport && transport.url) || ""
        };
      }
      """,
      [is_function: true],
      fn transport ->
        assert transport["connected"], "expected LiveSocket to be connected"

        assert transport["isWebSocket"],
               "expected WebSocket transport, got: #{inspect(transport)}"

        assert transport["open"], "expected open WebSocket transport, got: #{inspect(transport)}"

        assert transport["url"] =~ ~r|^wss?://[^/]+/live/websocket\b|,
               "expected LiveView WebSocket URL, got: #{inspect(transport["url"])}"
      end
    )
  end

  defp assert_inline_theme_initializer_runs_before_app_bundle(conn, expected_theme, timeout) do
    page_id = conn.page_id

    {:ok, _} =
      Page.route(
        page_id,
        "**/assets/app*.js*",
        fn route, _request ->
          {:ok, _} =
            Route.fulfill(route,
              status: 200,
              content_type: "application/javascript",
              body:
                "window.__themeBeforeAppBundle = document.documentElement.getAttribute('data-theme');"
            )
        end,
        timeout: timeout
      )

    try do
      conn
      |> visit(~p"/players/log_in")
      |> assert_enforced_nonce_csp(timeout)
      |> evaluate(
        """
        () => ({
          themeBeforeAppBundle: window.__themeBeforeAppBundle,
          liveSocketType: typeof window.liveSocket
        })
        """,
        [is_function: true],
        fn result ->
          assert result["liveSocketType"] == "undefined",
                 "expected external app.js bundle to be stubbed, got: #{inspect(result)}"

          assert result["themeBeforeAppBundle"] == expected_theme,
                 "expected inline theme script to apply #{inspect(expected_theme)} before app.js ran, got: #{inspect(result)}"
        end
      )
      |> assert_has("html[data-theme=#{expected_theme}]")
    after
      {:ok, _} = Page.unroute_all(page_id, timeout: timeout)
    end
  end

  defp header_value(%{name: name, value: value}, target) do
    if String.downcase(name) == target, do: value
  end
end
