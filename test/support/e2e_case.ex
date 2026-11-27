defmodule ForkaWeb.E2ECase do
  @moduledoc """
  ExUnit case template for Chromium browser tests (`@moduletag :e2e`).

  Use `async: false` for any test that creates a room, starts or interacts
  with a `Forka.Games.GameServer` (which runs under the application-level
  `Forka.GamesSupervisor`, outside the test and LiveView process trees), or
  depends on `"game_list"` PubSub broadcasts.

  In `async: false`, setup registers `on_exit` callbacks so teardown runs in
  strict LIFO order with no sleeps: close all browser contexts → synchronously
  terminate all `Forka.GamesSupervisor` children → stop the shared SQL sandbox
  owner and roll back the database transaction.

  Use `async: true` only for tests that never create a room, start a
  `GameServer`, or depend on a `"game_list"` broadcast (visiting `/` during
  login is safe because ExUnit runs all `async: true` modules before any
  `async: false` module).
  """

  use ExUnit.CaseTemplate
  use ForkaWeb, :verified_routes

  import PhoenixTest

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixTest.Playwright.Case, as: PlaywrightCase

  using opts do
    quote do
      use ForkaWeb, :verified_routes

      import Forka.Factory
      import ForkaWeb.E2ECase
      import PhoenixTest

      import PhoenixTest.Playwright,
        only: [
          add_cookies: 2,
          add_session_cookie: 3,
          assert_screenshot: 2,
          assert_screenshot: 3,
          clear_cookies: 1,
          clear_cookies: 2,
          click: 2,
          click: 3,
          click: 4,
          click_button: 4,
          click_link: 4,
          drag: 3,
          evaluate: 2,
          evaluate: 3,
          evaluate: 4,
          press: 3,
          press: 4,
          screenshot: 2,
          screenshot: 3,
          step: 3,
          type: 3,
          type: 4,
          visit: 3,
          with_dialog: 3
        ]

      @moduletag :e2e
      @moduletag Keyword.delete(unquote(opts), :async)
    end
  end

  setup_all context do
    PlaywrightCase.do_setup_all(context)
  end

  setup context do
    unless context.async do
      pid = Sandbox.start_owner!(Forka.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
      on_exit(fn -> terminate_game_servers() end)
    end

    PlaywrightCase.do_setup(context)
  end

  @doc """
  Signs a player in through the real `/players/log_in` form and waits for the
  room directory LiveView to connect and finish its initial async load.
  """
  def log_in(conn, player, password \\ "Password1!456") do
    conn
    |> visit(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> fill_in("E-mail ou nome de usuário", with: player.email)
    |> fill_in("Senha", with: password)
    |> click_button("Entrar")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
  end

  defp terminate_game_servers do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(Forka.GamesSupervisor),
        is_pid(pid) do
      DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
    end

    :ok
  end
end
