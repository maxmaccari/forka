defmodule ForkaWeb.E2E.RoomDirectoryTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: false` (shared sandbox)
  # because creating a room starts a `Forka.Games.GameServer` under
  # `Forka.GamesSupervisor` and broadcasts on the global `"game_list"` topic.
  use ForkaWeb.E2ECase, async: false

  test "E2E-03: signs a player in through the login form and shows the room list",
       %{conn: conn} do
    player = insert(:player, username: "lia")

    conn
    |> log_in(player)
    |> assert_has("h1", text: "Salas")
    |> assert_has("#rooms-live-status", text: "Ao vivo · nenhuma sala")
    |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")
    |> assert_has(~s|summary[aria-label="Conta"]|)
  end

  test "E2E-04: a second player in a separate browser session sees a newly created room appear live",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    guest = insert(:player, username: "bruno")

    other =
      context
      |> second_session()
      |> log_in(guest)
      |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")
      |> evaluate("window.forkaNoReload = true")

    conn
    |> log_in(owner)
    |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")
    |> click_button("#create-room-desktop", "Criar sala")
    |> assert_path(~p"/rooms/new")
    |> assert_has("[data-phx-main].phx-connected")
    |> fill_in("Nome da sala", with: "Noite de palavras")
    |> click_button("Criar sala")
    |> assert_has("h1", text: "Noite de palavras")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#room-invite-card")

    other
    |> refute_has("#rooms-empty")
    |> assert_has("#rooms-live-status", text: "Ao vivo · 1 sala")
    |> assert_has("#rooms-list", text: "Noite de palavras")
    |> assert_has("#rooms-list", text: "de lia")
    |> assert_has("#rooms-list", text: "1/4 jogadores")
    |> evaluate(
      "window.forkaNoReload",
      &assert(&1 == true, "expected live update without reload")
    )
  end
end
