defmodule ForkaWeb.E2E.InviteLobbyTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: false` (shared sandbox)
  # because creating rooms starts `Forka.Games.GameServer` children under
  # `Forka.GamesSupervisor` and broadcasts on global/room PubSub topics.
  use ForkaWeb.E2ECase, async: false

  alias Forka.Games
  alias Forka.Games.GameServer
  alias Forka.Scope
  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.Config
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Selector

  test "E2E-INV-01: invite sign-in, live lobby sync, copy confirmation, role controls, revisit, reload, and leave",
       %{conn: conn} = context do
    owner = insert(:player, username: "lia")
    guest = insert(:player, username: "bruno")
    empty_category = insert(:category, name: "Vazia", language: "pt")

    room =
      create_room!(owner, %{
        name: "Noite de palavras",
        max_players: 4,
        word_options: %{language: "pt", category_ids: [empty_category.id]}
      })

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

    # Done 2: Owner sees the new player appear in the roster live without a reload,
    # and positively sees desktop, mobile (DOM-attached + narrow viewport), and word-alert owner controls.
    owner_conn
    |> assert_has("#room-lobby-occupancy", text: "2/4 jogadores")
    |> assert_has("#room-lobby-player-#{guest.id}", text: "bruno")
    |> assert_has("#room-word-availability-alert")
    |> assert_has("#broaden-word-selection", text: "Ajustar configurações")
    |> assert_has("#edit-room-settings", text: "Editar")
    |> assert_has("#transfer-ownership-#{guest.id}", text: "Passar a posse")
    |> assert_in_dom("#transfer-ownership-mobile-#{guest.id}")
    |> with_viewport(375, 812, fn mobile_owner ->
      mobile_owner
      |> assert_has("#transfer-ownership-mobile-#{guest.id}")
      |> assert_has("#broaden-word-selection", text: "Ajustar configurações")
    end)
    |> evaluate(
      "window.forkaNoReload",
      &assert(&1 == true, "expected owner lobby to update live without reload")
    )

    # Done 4: Non-owner sees the word-availability alert itself, but has no owner controls
    # in the DOM (desktop, sm:hidden mobile transfer, or #broaden-word-selection) or on narrow viewports.
    guest_conn
    |> assert_has("#room-word-availability-alert")
    |> assert_has("#room-waiting-status", text: "Esperando lia começar")
    |> refute_has("#edit-room-settings")
    |> refute_has("#broaden-word-selection")
    |> refute_has(~s|[id^="transfer-ownership-"]|)
    |> refute_in_dom("#edit-room-settings")
    |> refute_in_dom("#broaden-word-selection")
    |> refute_in_dom(~s|[id^="transfer-ownership-"]|)
    |> with_viewport(375, 812, fn mobile_guest ->
      mobile_guest
      |> refute_has("#edit-room-settings")
      |> refute_has("#broaden-word-selection")
      |> refute_has(~s|[id^="transfer-ownership-"]|)
    end)

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

  test "E2E-INV-03: two players submit overlapping joins for the last seat; one enters the lobby and the other sees Sala cheia",
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

    game_pid = GameServer.whereis(room.id)
    assert is_pid(game_pid)
    invite_lv_pids = find_invite_live_pids(room.id)
    assert length(invite_lv_pids) == 2

    Enum.each(invite_lv_pids, &:erlang.trace(&1, true, [:send]))
    :ok = :sys.suspend(game_pid)

    {first_conn, second_conn} =
      try do
        first_conn =
          first_conn
          |> click_button("#invite-join-button", "Entrar na sala")
          |> assert_has("#invite-join-button.phx-click-loading")

        second_conn =
          second_conn
          |> click_button("#invite-join-button", "Entrar na sala")
          |> assert_has("#invite-join-button.phx-click-loading")

        first_id = first_player.id
        second_id = second_player.id

        assert_receive {:trace, _, :send, {:"$gen_call", _, {:join_room, ^first_id}}, ^game_pid},
                       2_000

        assert_receive {:trace, _, :send, {:"$gen_call", _, {:join_room, ^second_id}}, ^game_pid},
                       2_000

        {:messages, queued_messages} = Process.info(game_pid, :messages)

        assert Enum.any?(
                 queued_messages,
                 &match?({:"$gen_call", _, {:join_room, ^first_id}}, &1)
               )

        assert Enum.any?(
                 queued_messages,
                 &match?({:"$gen_call", _, {:join_room, ^second_id}}, &1)
               )

        {first_conn, second_conn}
      after
        Enum.each(invite_lv_pids, fn pid ->
          if Process.alive?(pid), do: :erlang.trace(pid, false, [:send])
        end)

        if Process.alive?(game_pid), do: :sys.resume(game_pid)
      end

    first_conn = await_join_outcome(first_conn)
    second_conn = await_join_outcome(second_conn)

    lobby_path = ~p"/rooms/#{room.id}"
    join_path = ~p"/rooms/#{room.id}/join"

    {winner, lobby_conn, loser, rejected_conn} =
      case {Playwright.current_path(first_conn), Playwright.current_path(second_conn)} do
        {^lobby_path, ^join_path} ->
          {first_player, first_conn, second_player, second_conn}

        {^join_path, ^lobby_path} ->
          {second_player, second_conn, first_player, first_conn}

        paths ->
          flunk("expected one lobby and one invite path, got: #{inspect(paths)}")
      end

    lobby_conn
    |> assert_path(lobby_path)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#room-lobby-occupancy", text: "2/2 jogadores")
    |> assert_has("#room-lobby-players > li[id^='room-lobby-player-']", count: 2)
    |> assert_has("#room-lobby-player-#{owner.id}", text: "lia")
    |> assert_has("#room-lobby-player-#{winner.id}", text: winner.username)
    |> refute_has("#room-lobby-player-#{loser.id}")

    rejected_conn
    |> assert_path(join_path)
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

  defp find_invite_live_pids(room_id) do
    Enum.filter(Process.list(), fn pid ->
      with {:dictionary, dict} <- Process.info(pid, :dictionary),
           {ForkaWeb.RoomInviteLive, :mount, 3} <- Keyword.get(dict, :"$initial_call") do
        try do
          match?(
            %{socket: %{view: ForkaWeb.RoomInviteLive, assigns: %{invite: %{id: ^room_id}}}},
            :sys.get_state(pid, 1_000)
          )
        catch
          :exit, _ -> false
        end
      else
        _ -> false
      end
    end)
  end

  defp await_join_outcome(conn) do
    conn
    |> refute_has("#invite-join-button")
    |> assert_has("#room-lobby-occupancy, #room-invite-card h2")
  end

  defp assert_in_dom(conn, selector) do
    unwrap(conn, fn %{frame_id: frame_id} ->
      {:ok, attached?} =
        Frame.expect(
          frame_id,
          expression: "to.be.attached",
          selector: selector |> Selector.css() |> Selector.concat(Selector.at(0)),
          timeout: Config.global(:timeout)
        )

      assert attached?, "expected #{inspect(selector)} to be attached in the DOM"
    end)
  end

  defp refute_in_dom(conn, selector) do
    unwrap(conn, fn %{frame_id: frame_id} ->
      {:ok, attached?} =
        Frame.expect(
          frame_id,
          expression: "to.be.attached",
          selector: selector |> Selector.css() |> Selector.concat(Selector.at(0)),
          is_not: true,
          timeout: Config.global(:timeout)
        )

      refute attached?, "expected #{inspect(selector)} to be absent from the DOM"
    end)
  end

  defp with_viewport(conn, width, height, fun) do
    {:ok, %{"width" => prev_w, "height" => prev_h}} =
      Frame.evaluate(conn.frame_id,
        expression: "() => ({width: window.innerWidth, height: window.innerHeight})",
        is_function: true,
        timeout: Config.global(:timeout)
      )

    conn = set_viewport(conn, width, height)

    try do
      fun.(conn)
    after
      set_viewport(conn, prev_w, prev_h)
    end
  end

  defp set_viewport(conn, width, height) do
    unwrap(conn, fn %{page_id: page_id} ->
      response =
        PlaywrightEx.send(
          %{
            guid: page_id,
            method: :set_viewport_size,
            params: %{viewportSize: %{width: width, height: height}}
          },
          timeout: Config.global(:timeout)
        )

      refute Map.has_key?(response, :error),
             "setViewportSize failed: #{inspect(response)}"
    end)
  end
end
