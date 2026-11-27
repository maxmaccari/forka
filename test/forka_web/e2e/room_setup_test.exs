defmodule ForkaWeb.E2E.RoomSetupTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: false` (shared sandbox)
  # because creating a room starts a `Forka.Games.GameServer` under
  # `Forka.GamesSupervisor` and broadcasts on the global `"game_list"` topic.
  use ForkaWeb.E2ECase, async: false

  test "MAX-51: empty directory, custom room setup, live directory sync, settings edit, and too-small word pool guidance",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    viewer = insert(:player, username: "bruno")

    _pt_cat = insert(:category, name: "Animais", language: "pt")
    en_music = insert(:category, name: "Music", language: "en")
    en_space = insert(:category, name: "Space", language: "en")
    en_rare = insert(:category, name: "Rare", language: "en")

    for text <- ~w(orbit comet nebula planet), do: insert(:word, text: text, category: en_space)
    for text <- ~w(piano guitar), do: insert(:word, text: text, category: en_music)
    insert(:word, text: "sphinx", category: en_rare)

    # DW-1 & DW-3 setup: second player sees the empty state and keeps the directory open
    viewer_session =
      context
      |> second_session()
      |> log_in(viewer)
      |> assert_has("h1", text: "Salas")
      |> assert_has("#rooms-live-status", text: "Ao vivo · nenhuma sala")
      |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")
      |> assert_has("#create-room-desktop", text: "Criar sala")
      |> evaluate("window.forkaNoReload = true")

    # DW-1 & DW-2: owner sees empty state + create action, creates room with non-default settings
    owner_session =
      conn
      |> log_in(owner)
      |> assert_has("#rooms-live-status", text: "Ao vivo · nenhuma sala")
      |> assert_has("#rooms-empty", text: "Nenhuma sala aberta")
      |> click_button("#create-room-desktop", "Criar sala")
      |> assert_path(~p"/rooms/new")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has(~s|#room-language [role="radio"][aria-checked="true"]|, text: "Português")
      |> assert_has(~s|#room-max-players [role="radio"][aria-checked="true"]|, text: "4")
      |> assert_has(~s|#category-chip-all[aria-pressed="true"]|)
      |> click(~s|#room-max-players [role="radio"]|, "6", exact: true)
      |> assert_has(~s|#room-max-players [role="radio"][aria-checked="true"]|, text: "6")
      |> assert_has("#room-words-note", text: "com 6 jogadores, são 12 palavras")
      |> click(~s|#room-language [role="radio"]|, "Inglês", exact: true)
      |> assert_has(~s|#room-language [role="radio"][aria-checked="true"]|, text: "Inglês")
      |> refute_has("button", text: "Animais")
      |> click_button("Space")
      |> assert_has(~s|button[aria-pressed="true"]|, text: "Space")
      |> click_button("Music")
      |> assert_has(~s|button[aria-pressed="true"]|, text: "Music")
      |> fill_in("Nome da sala", with: "Noite Estrelada")
      |> click_button("Criar sala")
      |> assert_has("h1", text: "Noite Estrelada")
      |> assert_has("[data-phx-main].phx-connected")
      |> evaluate("window.location.pathname", fn path ->
        assert path =~ ~r|^/rooms/[0-9a-f-]{36}$|
        send(self(), {:lobby_path, path})
      end)
      |> assert_has("#room-lobby-language", text: "Inglês")
      |> assert_has("#room-lobby-categories", text: "Music, Space")
      |> assert_has("#room-lobby-occupancy", text: "1/6 jogadores")
      |> assert_has("#room-lobby-words-requirement", text: "1 de 6 · 4 palavras (2 por jogador)")
      |> refute_has("#room-word-availability-alert")

    assert_receive {:lobby_path, lobby_path}

    # DW-3: second player sees the new room appear live without a reload
    viewer_session =
      viewer_session
      |> refute_has("#rooms-empty")
      |> assert_has("#rooms-live-status", text: "Ao vivo · 1 sala")
      |> assert_has("#rooms-list", text: "Noite Estrelada")
      |> assert_has("#rooms-list", text: "de lia · EN · 1/6 jogadores")
      |> assert_has("#rooms-list", text: "Music, Space")
      |> evaluate(
        "window.forkaNoReload",
        &assert(&1 == true, "expected live update without reload")
      )

    # DW-4: owner edits settings and the lobby shows the updated values
    owner_session =
      owner_session
      |> click_link("Editar")
      |> assert_path("#{lobby_path}/settings")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Configurações da sala")
      |> click(~s|#room-max-players [role="radio"]|, "3", exact: true)
      |> assert_has(~s|#room-max-players [role="radio"][aria-checked="true"]|, text: "3")
      |> fill_in("Nome da sala", with: "Noite de Foguetes")
      |> click_button("Salvar configurações")
      |> assert_path(lobby_path)
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Noite de Foguetes")
      |> assert_has("#room-lobby-occupancy", text: "1/3 jogadores")
      |> assert_has("#room-lobby-language", text: "Inglês")
      |> assert_has("#room-lobby-categories", text: "Music, Space")
      |> refute_has("#room-word-availability-alert")

    # Second player sees the updated settings live and joins so the lobby has 2 players
    viewer_session
    |> assert_has("#rooms-list", text: "Noite de Foguetes")
    |> assert_has("#rooms-list", text: "1/3 jogadores")
    |> evaluate(
      "window.forkaNoReload",
      &assert(&1 == true, "expected live update without reload")
    )
    |> click_button("Entrar na sala Noite de Foguetes")
    |> assert_path(lobby_path)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Noite de Foguetes")

    # DW-5: narrowing to a too-small word pool keeps the room in lobby with broadening guidance
    owner_session
    |> assert_has("#room-lobby-occupancy", text: "2/3 jogadores")
    |> assert_has("#room-waiting-status", text: "Sala pronta com 2 jogadores (4 palavras).")
    |> click_link("Editar")
    |> assert_path("#{lobby_path}/settings")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_button("Music")
    |> assert_has(~s|button[aria-pressed="false"]|, text: "Music")
    |> click_button("Space")
    |> assert_has(~s|button[aria-pressed="false"]|, text: "Space")
    |> click_button("Rare")
    |> assert_has(~s|button[aria-pressed="true"]|, text: "Rare")
    |> click_button("Salvar configurações")
    |> assert_path(lobby_path)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Noite de Foguetes")
    |> assert_has("main", text: "Aguardando jogadores")
    |> assert_has("#room-lobby-categories", text: "Rare")
    |> assert_has("#room-lobby-occupancy", text: "2/3 jogadores")
    |> assert_has("#room-lobby-language", text: "Inglês")
    |> assert_has("#room-word-availability-alert", text: "Poucas palavras para começar")
    |> assert_has("#room-word-availability-alert", text: "1 palavra válida")
    |> assert_has("#room-word-availability-alert", text: "escolha mais categorias")
    |> assert_has("#broaden-word-selection", text: "Ajustar configurações")
    |> assert_has(
      "#room-waiting-status",
      text: "Ajuste as configurações para ter palavras suficientes."
    )
  end
end
