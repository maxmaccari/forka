defmodule ForkaWeb.E2E.InviteLobbyTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: false` (shared sandbox)
  # because creating rooms starts `Forka.Games.GameServer` children under
  # `Forka.GamesSupervisor` and broadcasts on global/room PubSub topics.
  use ForkaWeb.E2ECase, async: false

  alias Forka.Games
  alias Forka.Scope
  alias PhoenixTest.Playwright.Config

  test "E2E-INV-01: invite sign-in, live lobby sync, copy confirmation, role controls, revisit, reload, and leave",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    guest = insert(:player, username: "bruno")
    room = create_room!(owner, %{name: "Noite de palavras", max_players: 4})
    expected_invite_url = url(~p"/rooms/#{room.id}/join")

    # Done 5: Owner opens lobby, copies invite link, sees confirmation, and clipboard holds URL.
    owner_conn =
      conn
      |> grant_clipboard_permissions()
      |> log_in(owner)
      |> visit(~p"/rooms/#{room.id}")
      |> assert_path(~p"/rooms/#{room.id}")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Noite de palavras")
      |> assert_has("#room-invite-card")
      |> assert_has("#room-invite-url", value: expected_invite_url)
      |> assert_has("#room-lobby-occupancy", text: "1/4 jogadores")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "lia")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")
      |> assert_has("#edit-room-settings", text: "Editar")
      |> evaluate("window.forkaNoReload = true")
      |> click_button("Copiar link")
      |> assert_has("#copy-invite-status", text: "Link copiado! Mande no grupo da turma.")
      |> evaluate(
        "() => navigator.clipboard.readText()",
        [is_function: true],
        &assert(&1 == expected_invite_url)
      )

    # Done 1: Signed-out guest opens invite link, signs in, returns to the invite page,
    # then clicks "Entrar na sala" to enter the lobby as a participant.
    guest_conn =
      context
      |> second_session()
      |> visit(~p"/rooms/#{room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Noite de palavras")
      |> assert_has("#room-invite-occupancy", text: "1/4 jogadores")
      |> assert_has("#room-invite-owner", text: "lia")
      |> click_link("#invite-login-link", "Entrar para jogar")
      |> assert_path(~p"/players/log_in", query_params: %{return_to: ~p"/rooms/#{room.id}/join"})
      |> assert_has("[data-phx-main].phx-connected")
      |> sign_in_through_form(guest)
      |> assert_path(~p"/rooms/#{room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#invite-join-button", text: "Entrar na sala")

    guest_conn =
      guest_conn
      |> click_button("Entrar na sala")
      |> assert_path(~p"/rooms/#{room.id}")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "lia")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "Anfitrião")
      |> assert_has("#room-lobby-player-#{guest.id}", text: "bruno")
      |> assert_has("#room-lobby-player-#{guest.id}", text: "· você")

    # Done 2: Owner sees the new player appear in the roster live without a reload.
    owner_conn
    |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
    |> assert_has("#room-lobby-player-#{guest.id}", text: "bruno")
    |> assert_has("#transfer-ownership-#{guest.id}", text: "Passar a posse")
    |> evaluate(
      "window.forkaNoReload",
      &assert(&1 == true, "expected owner lobby to update live without reload")
    )

    # Done 4: Non-owner does not see owner controls (edit settings or transfer ownership).
    guest_conn
    |> refute_has("#edit-room-settings")
    |> refute_has(~s|[id^="transfer-ownership-"]|)
    |> assert_has("#room-waiting-status", text: "Esperando lia começar")

    # Edge B: Participant reopens invite link and returns to lobby without joining twice.
    guest_conn =
      guest_conn
      |> visit(~p"/rooms/#{room.id}/join")
      |> assert_path(~p"/rooms/#{room.id}")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
      |> assert_has("#room-lobby-players > li[id^='room-lobby-player-']", count: 2)
      |> assert_has("#room-lobby-player-#{guest.id}", text: "bruno")

    # Edge C: Reloading the lobby keeps the player in the roster for both browsers.
    guest_conn =
      guest_conn
      |> evaluate("window.forkaReloadProbe = true")
      |> reload_page()
      |> assert_path(~p"/rooms/#{room.id}")
      |> assert_has("[data-phx-main].phx-connected")
      |> evaluate(
        "window.forkaReloadProbe === undefined",
        &assert(&1 == true, "expected browser page reload")
      )
      |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
      |> assert_has("#room-lobby-player-#{owner.id}", text: "lia")
      |> assert_has("#room-lobby-player-#{guest.id}", text: "bruno")

    owner_conn
    |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
    |> assert_has("#room-lobby-player-#{guest.id}", text: "bruno")
    |> evaluate(
      "window.forkaNoReload",
      &assert(&1 == true, "expected owner lobby to remain live without reload")
    )

    # Done 6: Guest leaves before the match and disappears from the owner's roster live.
    guest_conn
    |> click_button("Sair da sala")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-info", text: "Você saiu da sala.")

    owner_conn
    |> refute_has("#room-lobby-player-#{guest.id}")
    |> assert_has("#room-lobby-occupancy", text: "1/4 jogadores")
    |> evaluate(
      "window.forkaNoReload",
      &assert(&1 == true, "expected owner lobby to reflect leave without reload")
    )
  end

  test "E2E-INV-02: full and archived room invite links show their state and lead back to the room list",
       %{conn: conn} do
    owner = insert(:player, username: "lia")
    seat2 = insert(:player, username: "bruno")
    outsider = insert(:player, username: "caio")

    full_room = create_room!(owner, %{name: "Sala Lotada", max_players: 2})
    {:ok, :joined} = Games.join_room(Scope.for_player(seat2), full_room.id)

    archived_room = create_room!(owner, %{name: "Sala Arquivada", max_players: 4})
    :ok = Games.leave_game(Scope.for_player(owner), archived_room.id, confirm: :archive)

    outsider_conn =
      conn
      |> log_in(outsider)
      |> visit(~p"/rooms/#{full_room.id}/join")
      |> assert_path(~p"/rooms/#{full_room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Sala Lotada")
      |> assert_has("#room-invite-occupancy", text: "2/2 jogadores")
      |> assert_has("h2", text: "Sala cheia")
      |> assert_has("#room-invite-card", text: "Esta sala já atingiu o limite de jogadores.")
      |> refute_has("#invite-join-button")
      |> click_link("#invite-directory-link", "Voltar para as salas")
      |> assert_path(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Salas")
      |> assert_has("#rooms-live-status", text: "Ao vivo")

    outsider_conn
    |> visit(~p"/rooms/#{archived_room.id}/join")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-error", text: "Esta sala foi arquivada.")
    |> assert_has("h1", text: "Salas")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
  end

  test "E2E-INV-03: two players open the stale invite for the last seat; first joins and second sees Sala cheia",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    first_player = insert(:player, username: "bruno")
    second_player = insert(:player, username: "caio")
    room = create_room!(owner, %{name: "Última vaga", max_players: 2})

    first_conn =
      conn
      |> log_in(first_player)
      |> visit(~p"/rooms/#{room.id}/join")
      |> assert_path(~p"/rooms/#{room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#room-invite-occupancy", text: "1/2 jogadores")
      |> assert_has("#invite-join-button", text: "Entrar na sala")

    second_conn =
      context
      |> second_session()
      |> log_in(second_player)
      |> visit(~p"/rooms/#{room.id}/join")
      |> assert_path(~p"/rooms/#{room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#room-invite-occupancy", text: "1/2 jogadores")
      |> assert_has("#invite-join-button", text: "Entrar na sala")

    first_conn
    |> click_button("Entrar na sala")
    |> assert_path(~p"/rooms/#{room.id}")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#room-lobby-occupancy", text: "2/2 jogadores")
    |> assert_has("#room-lobby-player-#{first_player.id}", text: "bruno")

    second_conn
    |> click_button("Entrar na sala")
    |> assert_path(~p"/rooms/#{room.id}/join")
    |> assert_has("h2", text: "Sala cheia")
    |> assert_has("#room-invite-occupancy", text: "2/2 jogadores")
    |> refute_has("#invite-join-button")
    |> assert_has("#invite-directory-link", text: "Voltar para as salas")
  end

  test "E2E-INV-04: owner leaves alone and archives the room while a player holds the stale invite page",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    invitee = insert(:player, username: "bruno")
    room = create_room!(owner, %{name: "Sala que fecha", max_players: 4})

    owner_conn =
      conn
      |> log_in(owner)
      |> visit(~p"/rooms/#{room.id}")
      |> assert_path(~p"/rooms/#{room.id}")
      |> assert_has("[data-phx-main].phx-connected")

    invitee_conn =
      context
      |> second_session()
      |> log_in(invitee)
      |> visit(~p"/rooms/#{room.id}/join")
      |> assert_path(~p"/rooms/#{room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#invite-join-button", text: "Entrar na sala")

    owner_conn
    |> click_button("Sair da sala")
    |> assert_has(
      "#leave-room-confirm",
      text: "Você é a última pessoa na sala. Ao sair, ela será arquivada."
    )
    |> click_button("Sair e arquivar a sala")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-info", text: "Você saiu da sala.")

    invitee_conn
    |> click_button("Entrar na sala")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-error", text: "Esta sala foi arquivada.")
    |> assert_has("h1", text: "Salas")
  end

  test "E2E-INV-05: owner hands off room while invitee holds stale invite; join works with new Anfitrião",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    co_player = insert(:player, username: "carla")
    invitee = insert(:player, username: "bruno")
    room = create_room!(owner, %{name: "Sala que continua", max_players: 4})
    {:ok, :joined} = Games.join_room(Scope.for_player(co_player), room.id)

    owner_conn =
      conn
      |> log_in(owner)
      |> visit(~p"/rooms/#{room.id}")
      |> assert_path(~p"/rooms/#{room.id}")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")

    invitee_conn =
      context
      |> second_session()
      |> log_in(invitee)
      |> visit(~p"/rooms/#{room.id}/join")
      |> assert_path(~p"/rooms/#{room.id}/join")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#room-invite-owner", text: "lia")
      |> assert_has("#invite-join-button", text: "Entrar na sala")

    owner_conn
    |> click_button("Sair da sala")
    |> assert_has("#leave-room-confirm", text: "A sala passa para carla.")
    |> click_button("Sair e passar a sala")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-info", text: "Você saiu da sala.")

    invitee_conn
    |> click_button("Entrar na sala")
    |> assert_path(~p"/rooms/#{room.id}")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
    |> assert_has("#room-lobby-player-#{co_player.id}", text: "carla")
    |> assert_has("#room-lobby-player-#{co_player.id}", text: "Anfitrião")
    |> assert_has("#room-lobby-player-#{invitee.id}", text: "bruno")
    |> assert_has("#room-lobby-player-#{invitee.id}", text: "· você")
    |> refute_has("#room-lobby-player-#{owner.id}")
    |> assert_has("#room-waiting-status", text: "Esperando carla começar")
    |> refute_has("#edit-room-settings")
  end

  defp create_room!(owner, params) do
    {:ok, room} = Games.create_room(Scope.for_player(owner), params)
    room
  end

  defp sign_in_through_form(conn, player, password \\ "Password1!456") do
    conn
    |> fill_in("E-mail ou nome de usuário", with: player.email)
    |> fill_in("Senha", with: password)
    |> click_button("Entrar")
  end

  defp grant_clipboard_permissions(conn) do
    unwrap(conn, fn %{context_id: context_id} ->
      # grantPermissions is a void protocol method: success replies `%{id: _}`
      # with no `:result` key; failure replies with an `:error` key.
      response =
        PlaywrightEx.send(
          %{
            guid: context_id,
            method: :grant_permissions,
            params: %{permissions: ["clipboard-read", "clipboard-write"]}
          },
          timeout: Config.global(:timeout)
        )

      refute Map.has_key?(response, :error),
             "grantPermissions failed: #{inspect(response)}"
    end)
  end
end
