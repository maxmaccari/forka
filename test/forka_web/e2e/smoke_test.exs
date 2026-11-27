defmodule ForkaWeb.E2E.SmokeTest do
  # Runs in Chromium (`mix test.e2e`). Checks what LiveViewTest cannot, since
  # LiveViewTest never runs a browser: LiveView connects over WebSocket and the
  # nonced theme script toggles themes without CSP violations.
  use ForkaWeb.E2ECase, async: true

  import ExUnit.CaptureLog

  test "E2E-01: a LiveView page connects and runs the nonced theme script without CSP violations",
       %{conn: conn} do
    log =
      capture_log(fn ->
        conn
        |> visit(~p"/players/log_in")
        |> assert_has("[data-phx-main].phx-connected")
        |> click_button("Tema: sistema. Trocar tema")
        |> assert_has("html[data-theme=light]")
        |> assert_has(~s|button[aria-label="Tema: claro. Trocar tema"]|)
      end)

    refute log =~ "Content Security Policy"
  end
end
