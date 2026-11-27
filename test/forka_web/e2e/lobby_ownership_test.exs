defmodule ForkaWeb.E2E.LobbyOwnershipTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: false` (shared sandbox)
  # because rooms run under `Forka.GamesSupervisor` and broadcast on PubSub
  # topics (`"room_lobby:*"` and `"game_list"`).
  use ForkaWeb.E2ECase, async: false

  alias Forka.Games
  alias Forka.Scope

  test "MAX-53 DW-01: owner transfers ownership in two browsers without a reload",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    guest = insert(:player, username: "bruno")
    insert_list(4, :word)

    {:ok, game} = Games.create_game(owner.id, %{name: "Sala Posse", max_players: 4})
    {:ok, :joined} = Games.join_room(Scope.for_player(guest), game.id)

    owner_session =
      conn
      |> log_in(owner)
      |> visit_lobby(game.id, "Sala Posse")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")
      |> refute_has("#room-lobby-player-#{guest.id}", text: "Anfitrião")
      |> assert_has("#edit-room-settings", text: "Editar")
      |> assert_has("#transfer-ownership-#{guest.id}", text: "Passar a posse")
      |> assert_has("#room-waiting-status", text: "Sala pronta com 2 jogadores")
      |> mark_no_reload()

    guest_session =
      context
      |> second_session()
      |> log_in(guest)
      |> visit_lobby(game.id, "Sala Posse")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")
      |> refute_has("#edit-room-settings")
      |> refute_has("#transfer-ownership-#{owner.id}")
      |> assert_has("#room-waiting-status", text: "Esperando lia começar")
      |> mark_no_reload()

    owner_session
    |> click_button("#transfer-ownership-#{guest.id}", "Passar a posse")
    |> assert_has("#transfer-ownership-sheet", text: "Passar a sala para bruno?")
    |> click_button("#confirm-transfer-ownership", "Passar a posse")
    |> refute_has("#transfer-ownership-sheet")
    |> assert_path(~p"/rooms/#{game.id}")
    |> assert_has("#room-lobby-player-#{guest.id}", text: "Anfitrião")
    |> refute_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")
    |> refute_has("#edit-room-settings")
    |> refute_has("#transfer-ownership-#{guest.id}")
    |> assert_has("#room-waiting-status", text: "Esperando bruno começar")
    |> assert_has("#room-lobby-notice", text: "Agora bruno comanda a sala.")
    |> assert_no_reload("expected former owner lobby update without reload")

    guest_session
    |> assert_path(~p"/rooms/#{game.id}")
    |> assert_has("#room-lobby-player-#{guest.id}", text: "Anfitrião")
    |> refute_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")
    |> assert_has("#edit-room-settings", text: "Editar")
    |> assert_has("#transfer-ownership-#{owner.id}", text: "Passar a posse")
    |> assert_has("#room-waiting-status", text: "Sala pronta com 2 jogadores")
    |> assert_has("#room-lobby-notice", text: "Agora você comanda a sala.")
    |> assert_no_reload("expected new owner lobby update without reload")
  end

  test "MAX-53 DW-02 & DW-03: owner leave hands off live and last leave archives room",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    guest = insert(:player, username: "bruno")

    {:ok, game} = Games.create_game(owner.id, %{name: "Sala Saída", max_players: 4})
    {:ok, :joined} = Games.join_room(Scope.for_player(guest), game.id)

    owner_session =
      conn
      |> log_in(owner)
      |> visit_lobby(game.id, "Sala Saída")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")

    guest_session =
      context
      |> second_session()
      |> log_in(guest)
      |> visit_lobby(game.id, "Sala Saída")
      |> assert_has("#room-waiting-status", text: "Esperando lia começar")
      |> refute_has("#edit-room-settings")
      |> mark_no_reload()

    # DW-02: owner leaves while another player remains -> automatic handoff live
    owner_session =
      owner_session
      |> click_button("Sair da sala")
      |> assert_has("#leave-room-confirm", text: "A sala passa para bruno.")
      |> click_button("Sair e passar a sala")
      |> assert_path(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#flash-info", text: "Você saiu da sala.")
      |> assert_has("#rooms-live-status", text: "Ao vivo · 1 sala")
      |> assert_has("#rooms-list", text: "Sala Saída")
      |> assert_has("#rooms-list", text: "de bruno")
      |> assert_has("#rooms-list", text: "1/4 jogadores")
      |> mark_no_reload()

    guest_session =
      guest_session
      |> assert_path(~p"/rooms/#{game.id}")
      |> refute_has("#room-lobby-player-#{owner.id}")
      |> assert_has("#room-lobby-player-#{guest.id}", text: "Anfitrião")
      |> assert_has("#edit-room-settings", text: "Editar")
      |> assert_has("#room-lobby-notice", text: "Agora você comanda a sala.")
      |> assert_has("#room-lobby-occupancy", text: "1/4 jogadores")
      |> assert_has(
        "#room-waiting-status",
        text: "Aguardando pelo menos mais 1 jogador para começar"
      )
      |> assert_no_reload("expected remaining player to see new owner without reload")

    # DW-03: last player leaves -> room archived, removed live from directory, URL says archived
    guest_session
    |> click_button("Sair da sala")
    |> assert_has(
      "#leave-room-confirm",
      text: "Você é a última pessoa na sala. Ao sair, ela será arquivada."
    )
    |> click_button("Sair e arquivar a sala")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-info", text: "Você saiu da sala.")
    |> assert_has("#rooms-live-status", text: "Ao vivo · nenhuma sala")
    |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")

    owner_session
    |> refute_has("#rooms-list", text: "Sala Saída")
    |> assert_has("#rooms-live-status", text: "Ao vivo · nenhuma sala")
    |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")
    |> assert_no_reload("expected archived room to disappear from directory without reload")
    |> visit(~p"/rooms/#{game.id}")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-error", text: "Esta sala foi arquivada.")
  end

  defp visit_lobby(session, game_id, room_name) do
    session
    |> visit(~p"/rooms/#{game_id}")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: room_name)
  end

  defp mark_no_reload(session) do
    evaluate(session, "window.forkaNoReload = true")
  end

  defp assert_no_reload(session, message) do
    evaluate(session, "window.forkaNoReload", &assert(&1 == true, message))
  end
end
