defmodule ForkaWeb.RoomLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Forka.Games
  alias Forka.Games.GameServer

  describe "GET /rooms/:id" do
    test "AC-05: redirects unauthenticated visitor to login", %{conn: conn} do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Privada", max_players: 4})

      assert {:error, {:redirect, %{to: "/players/log_in"}}} = live(conn, ~p"/rooms/#{game.id}")
    end

    test "AC-05: renders room lobby details and owner settings link for owner in lobby", %{
      conn: conn
    } do
      owner = insert(:player, username: "lia")
      cat = insert(:category, name: "Música", language: "pt")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Noite de palavras",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      {:ok, lv, html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      text = visible_text(html)

      assert page_title(lv) =~ "Noite de palavras"
      assert text =~ "Noite de palavras"
      assert text =~ "1/6 jogadores"
      assert text =~ "Português"
      assert text =~ "Música"
      assert text =~ "lia"
      assert has_element?(lv, ~s|#edit-room-settings[href="/rooms/#{game.id}/settings"]|)
    end

    test "AC-05: renders room created without word_options using safe defaults", %{conn: conn} do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sem opções", max_players: 4})

      {:ok, _lv, html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      text = visible_text(html)

      assert text =~ "Sem opções"
      assert text =~ "1/4 jogadores"
      assert text =~ "Inglês"
      assert text =~ "Todas as categorias"
    end

    test "AC-05: hides owner settings link for non-owner players", %{conn: conn} do
      owner = insert(:player, username: "lia")
      other = insert(:player, username: "bruno")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala da Lia",
          max_players: 4,
          word_options: %{language: "pt", category_ids: []}
        })

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(other), game.id)

      {:ok, lv, html} = conn |> log_in_player(other) |> live(~p"/rooms/#{game.id}")
      assert visible_text(html) =~ "Todas as categorias"
      refute has_element?(lv, "#edit-room-settings")
    end

    test "REQ-07: redirects seated participants to match page when opening room URL after start",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala jogando", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)
      insert_list(4, :word)
      :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      for player <- [owner, guest] do
        assert {:error, {:live_redirect, %{to: redirect_to}}} =
                 conn |> log_in_player(player) |> live(~p"/rooms/#{game.id}")

        assert redirect_to == ~p"/rooms/#{game.id}/match"
      end
    end

    test "AC-05: redirects to directory with flash when room does not exist or ID is invalid",
         %{conn: conn} do
      player = insert(:player)
      missing_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Sala não encontrada."}}}} =
               conn |> log_in_player(player) |> live(~p"/rooms/#{missing_id}")

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Sala não encontrada."}}}} =
               conn |> log_in_player(player) |> live(~p"/rooms/not-a-uuid")
    end

    test "AC-05: redirects to directory with flash when reopening an archived room", %{
      conn: conn
    } do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Arquivada", max_players: 4})

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      :ok = Games.archive_game(Forka.Scope.for_player(owner), game.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert {:error,
              {:live_redirect, %{to: "/", flash: %{"error" => "Esta sala foi arquivada."}}}} =
               conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
    end

    test "AC-05: receives live room lobby updates after mounting", %{conn: conn} do
      owner = insert(:player, username: "lia")
      viewer = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      cat = insert(:category, name: "Cinema", language: "pt")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Inicial", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(viewer), game.id)

      {:ok, lv, _html} = conn |> log_in_player(viewer) |> live(~p"/rooms/#{game.id}")

      :ok =
        Games.update_room_settings(owner_scope, game.id, %{
          name: "Sala Renovada",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      text = lv |> render() |> visible_text()
      assert text =~ "Sala Renovada"
      assert text =~ "2/6 jogadores"
      assert text =~ "Português"
      assert text =~ "Cinema"
    end

    test "REQ-02 & REQ-06: invite card keeps ShareInvite DOM under phx-update=ignore and updates data-title on rename",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      owner_scope = Forka.Scope.for_player(owner)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Inicial", max_players: 4})
      {:ok, lv, _html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")

      assert has_element?(
               lv,
               ~s|#room-invite-card[phx-hook="ShareInvite"][phx-update="ignore"][data-title="Sala Inicial"][data-url$="/rooms/#{game.id}/join"]|
             )

      assert has_element?(
               lv,
               ~s|#room-invite-card[phx-update="ignore"] #share-invite-link[data-share-invite]|
             )

      assert has_element?(
               lv,
               ~s|#room-invite-card[phx-update="ignore"] #copy-invite-status[data-share-status]|
             )

      :ok =
        Games.update_room_settings(owner_scope, game.id, %{
          name: "Sala Renomeada"
        })

      _ = render(lv)

      assert has_element?(
               lv,
               ~s|#room-invite-card[phx-hook="ShareInvite"][phx-update="ignore"][data-title="Sala Renomeada"][data-url$="/rooms/#{game.id}/join"]|
             )

      assert has_element?(
               lv,
               ~s|#room-invite-card[phx-update="ignore"] #share-invite-link[data-share-invite]|
             )

      assert has_element?(
               lv,
               ~s|#room-invite-card[phx-update="ignore"] #copy-invite-status[data-share-status]|
             )
    end

    test "REQ-05 & REQ-06: shows word requirement and updates broadening alert live on join, leave, and settings change",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")
      owner_scope = Forka.Scope.for_player(owner)

      cat_small = insert(:category, name: "Pequena", language: "pt")
      cat_extra = insert(:category, name: "Extra", language: "pt")

      for text <- ~w(alfa bravo charlie delta) do
        insert(:word, text: text, category: cat_small)
      end

      for text <- ~w(eco foxtrot) do
        insert(:word, text: text, category: cat_extra)
      end

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Noite de palavras",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat_small.id]}
        })

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p2), game.id)

      {:ok, lv, html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      assert visible_text(html) =~ "2 de 6 · 4 palavras (2 por jogador)"
      refute has_element?(lv, "#room-word-availability-alert")

      # 3rd player joins -> required rises to 6 while pool has 4 -> alert appears with owner link
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p3), game.id)
      joined_text = lv |> render() |> visible_text()
      assert joined_text =~ "3 de 6 · 6 palavras (2 por jogador)"
      assert has_element?(lv, "#room-word-availability-alert")
      assert joined_text =~ "Poucas palavras para começar"
      assert joined_text =~ "4 palavras válidas"
      assert joined_text =~ "Todas as categorias"

      assert has_element?(
               lv,
               ~s|#broaden-word-selection[href="/rooms/#{game.id}/settings"]|
             )

      # 3rd player leaves -> required returns to 4 -> alert disappears
      :ok = Games.leave_game(Forka.Scope.for_player(p3), game.id)
      left_text = lv |> render() |> visible_text()
      assert left_text =~ "2 de 6 · 4 palavras (2 por jogador)"
      refute has_element?(lv, "#room-word-availability-alert")

      # 3rd player rejoins, then owner broadens categories -> alert disappears
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p3), game.id)
      assert has_element?(lv, "#room-word-availability-alert")

      :ok =
        Games.update_room_settings(owner_scope, game.id, %{
          word_options: %{language: "pt", category_ids: [cat_small.id, cat_extra.id]}
        })

      _ = render(lv)
      refute has_element?(lv, "#room-word-availability-alert")
    end

    test "REQ-06: hides owner settings action inside word alert for non-owner viewers", %{
      conn: conn
    } do
      owner = insert(:player, username: "lia")
      viewer = insert(:player, username: "bruno")
      cat_empty = insert(:category, name: "Vazia", language: "pt")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala Vazia",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [cat_empty.id]}
        })

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(viewer), game.id)

      {:ok, lv, html} = conn |> log_in_player(viewer) |> live(~p"/rooms/#{game.id}")
      assert has_element?(lv, "#room-word-availability-alert")
      assert visible_text(html) =~ "0 palavras válidas"
      refute has_element?(lv, "#broaden-word-selection")
    end

    test "blocks kickoff and shows lobby guidance when excluding unsupported-letter words leaves too few words",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      cat = insert(:category, name: "Mistura", language: "pt")

      for text <- ~w(alfa bravo charlie straße) do
        insert(:word, text: text, category: cat)
      end

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala Alemã",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      assert {:error, {:insufficient_words, %{available: 3, required: 4}}} =
               Games.start_game(Forka.Scope.for_player(owner), game.id)

      {:ok, lv, html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      text = visible_text(html)

      assert text =~ "Aguardando jogadores"
      assert text =~ "2 de 4 · 4 palavras (2 por jogador)"
      assert has_element?(lv, "#room-word-availability-alert")
      assert text =~ "Poucas palavras para começar"
      assert text =~ "3 palavras válidas"
      assert text =~ "Todas as categorias"

      assert has_element?(
               lv,
               ~s|#broaden-word-selection[href="/rooms/#{game.id}/settings"]|
             )
    end

    test "REQ-08: redirects signed-in non-seated visitor to the join page", %{conn: conn} do
      owner = insert(:player, username: "lia")
      outsider = insert(:player, username: "caio")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Aberta", max_players: 4})

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               conn |> log_in_player(outsider) |> live(~p"/rooms/#{game.id}")

      assert redirect_to == ~p"/rooms/#{game.id}/join"
    end

    test "REQ-01 & REQ-02 & REQ-03 & EDGE-04: renders full lobby for owner with invite link, empty seats, settings, waiting status, leave button, and no start button",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      cat = insert(:category, name: "Música", language: "pt")

      for text <- ~w(samba bossa frevo choro), do: insert(:word, text: text, category: cat)

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Noite de palavras",
          max_players: 4,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      {:ok, lv, html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      text = visible_text(html)

      assert text =~ "Sala de espera"
      assert text =~ "Noite de palavras"
      assert text =~ "1 de 4 · 4 palavras (2 por jogador)"
      assert text =~ "1/4 jogadores"
      assert text =~ "lia · você"
      assert text =~ "Anfitrião"
      assert has_element?(lv, "#room-lobby-empty-seat-1")
      assert has_element?(lv, "#room-lobby-empty-seat-2")
      assert has_element?(lv, "#room-lobby-empty-seat-3")
      refute has_element?(lv, "#room-lobby-empty-seat-4")
      assert has_element?(lv, ~s|#room-invite-url[value$="/rooms/#{game.id}/join"]|)
      assert has_element?(lv, "#copy-invite-link")
      assert has_element?(lv, "#room-waiting-status", "Aguardando pelo menos mais 1 jogador")
      assert has_element?(lv, ~s|#edit-room-settings[href="/rooms/#{game.id}/settings"]|)
      assert has_element?(lv, "#leave-room-button", "Sair da sala")
      refute text =~ "Começar partida"
      refute text =~ "Passar a posse"

      # When another player joins and max_players is lowered to 2 (full), empty seats disappear
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      :ok =
        Games.update_room_settings(Forka.Scope.for_player(owner), game.id, %{max_players: 2})

      full_text = lv |> render() |> visible_text()
      assert full_text =~ "2 de 2 · 4 palavras (2 por jogador)"
      assert full_text =~ "Sala pronta com 2 jogadores (4 palavras)."
      refute has_element?(lv, "#room-lobby-empty-seat-1")
      refute full_text =~ "Lugar livre"
    end

    test "REQ-01 & REQ-03: renders non-owner lobby with waiting message, invite link, leave button, and no edit settings link",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} =
        Games.create_game(owner.id, %{
          name: "Sala da Lia",
          max_players: 4,
          word_options: %{language: "pt", category_ids: []}
        })

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      {:ok, lv, html} = conn |> log_in_player(guest) |> live(~p"/rooms/#{game.id}")
      text = visible_text(html)

      assert text =~ "lia"
      assert text =~ "bruno · você"
      assert text =~ "Anfitrião"
      assert has_element?(lv, "#room-lobby-empty-seat-1")
      assert has_element?(lv, "#room-lobby-empty-seat-2")
      assert has_element?(lv, ~s|#room-invite-url[value$="/rooms/#{game.id}/join"]|)
      assert has_element?(lv, "#room-waiting-status", "Esperando lia começar")
      assert has_element?(lv, "#leave-room-button", "Sair da sala")
      refute has_element?(lv, "#edit-room-settings")
      refute text =~ "Começar partida"
    end
  end

  describe "pre-match leave and live lobby transitions" do
    test "REQ-04 & REQ-06: non-owner leaves live, redirects to directory, and updates remaining lobby",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Live", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      {:ok, owner_lv, _html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      guest_conn = build_conn() |> log_in_player(guest)
      {:ok, guest_lv, _html} = live(guest_conn, ~p"/rooms/#{game.id}")

      assert has_element?(owner_lv, "#room-lobby-player-#{guest.id}")

      {:ok, _dir_lv, dir_html} =
        guest_lv
        |> element("#leave-room-button")
        |> render_click()
        |> follow_redirect(guest_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."

      owner_text = owner_lv |> render() |> visible_text()
      refute has_element?(owner_lv, "#room-lobby-player-#{guest.id}")
      assert has_element?(owner_lv, "#room-lobby-empty-seat-3")
      assert owner_text =~ "1/4 jogadores"
      assert owner_text =~ "1 de 4 · 4 palavras (2 por jogador)"
    end

    test "REQ-04 & REQ-06: owner leaves live, hands ownership to lowest seat, and switches controls on connected clients",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Troca", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p2), game.id)
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(p3), game.id)

      owner_conn = conn |> log_in_player(owner)
      {:ok, owner_lv, _html} = live(owner_conn, ~p"/rooms/#{game.id}")
      {:ok, p2_lv, _html} = build_conn() |> log_in_player(p2) |> live(~p"/rooms/#{game.id}")
      {:ok, p3_lv, _html} = build_conn() |> log_in_player(p3) |> live(~p"/rooms/#{game.id}")

      refute has_element?(p2_lv, "#edit-room-settings")
      assert has_element?(p3_lv, "#room-waiting-status", "Esperando lia começar")

      # Owner leave asks first and names the next owner (lowest remaining seat)
      refute has_element?(owner_lv, "#leave-room-confirm")
      owner_lv |> element("#leave-room-button") |> render_click()
      assert has_element?(owner_lv, "#leave-room-confirm", "A sala passa para bruno.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e passar a sala")

      assert has_element?(
               owner_lv,
               "#leave-room-confirm",
               "Você pode voltar pelo link de convite."
             )

      assert has_element?(p2_lv, "#room-lobby-player-#{owner.id}")

      {:ok, _dir_lv, dir_html} =
        owner_lv
        |> element("#confirm-leave-room")
        |> render_click()
        |> follow_redirect(owner_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."

      p2_text = p2_lv |> render() |> visible_text()
      assert has_element?(p2_lv, ~s|#edit-room-settings[href="/rooms/#{game.id}/settings"]|)

      assert visible_text(element(p2_lv, "#room-lobby-player-#{p2.id}") |> render()) =~
               "Anfitrião"

      assert has_element?(p2_lv, "#room-lobby-notice", "Agora você comanda a sala.")
      refute has_element?(p2_lv, "#room-lobby-player-#{owner.id}")
      assert p2_text =~ "2/4 jogadores"

      p3_text = p3_lv |> render() |> visible_text()
      refute has_element?(p3_lv, "#edit-room-settings")
      assert has_element?(p3_lv, "#room-waiting-status", "Esperando bruno começar")
      assert has_element?(p3_lv, "#room-lobby-notice", "Agora bruno comanda a sala.")
      assert p3_text =~ "2/4 jogadores"
    end

    test "REQ-05: last player leaving archives room, stops GameServer, and redirects to directory",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Último", max_players: 4})

      owner_conn = conn |> log_in_player(owner)
      {:ok, lv, _html} = live(owner_conn, ~p"/rooms/#{game.id}")

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)

      # Cancel keeps the room and the seat
      lv |> element("#leave-room-button") |> render_click()
      assert has_element?(lv, "#leave-room-confirm", "Ao sair, ela será arquivada.")
      refute has_element?(lv, "#leave-room-confirm", "Você pode voltar pelo link de convite.")
      lv |> element("#cancel-leave-room") |> render_click()
      refute has_element?(lv, "#leave-room-confirm")
      assert has_element?(lv, "#room-lobby-player-#{owner.id}")

      lv |> element("#leave-room-button") |> render_click()
      assert has_element?(lv, "#confirm-leave-room", "Sair e arquivar a sala")

      {:ok, _dir_lv, dir_html} =
        lv
        |> element("#confirm-leave-room")
        |> render_click()
        |> follow_redirect(owner_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert {:error, :game_archived} =
               Games.get_room_lobby(Forka.Scope.for_player(owner), game.id)
    end

    test "REQ-07: routes every connected lobby participant live to match page when game starts",
         %{
           conn: conn
         } do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      insert_list(4, :word)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Início", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      {:ok, owner_lv, _html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      {:ok, guest_lv, _html} = build_conn() |> log_in_player(guest) |> live(~p"/rooms/#{game.id}")

      assert :ok = Games.start_game(Forka.Scope.for_player(owner), game.id)

      assert_redirect(owner_lv, ~p"/rooms/#{game.id}/match")
      assert_redirect(guest_lv, ~p"/rooms/#{game.id}/match")
    end

    test "EDGE-03: mounted lobby client redirects to directory when room is archived", %{
      conn: conn
    } do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Arquivar", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      {:ok, guest_lv, _html} = conn |> log_in_player(guest) |> live(~p"/rooms/#{game.id}")

      assert :ok = Games.archive_game(Forka.Scope.for_player(owner), game.id)
      assert_redirect(guest_lv, ~p"/")
    end

    test "EDGE-05: mounted lobby client redirects to directory if viewer leaves from another session",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Duas Abas", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      {:ok, tab1_lv, _html} = conn |> log_in_player(guest) |> live(~p"/rooms/#{game.id}")
      assert :ok = Games.leave_game(Forka.Scope.for_player(guest), game.id)

      assert_redirect(tab1_lv, ~p"/")
    end

    test "REQ-08: forged leave_room payload cannot remove another player or affect another room",
         %{
           conn: conn
         } do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Segura", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      guest_conn = conn |> log_in_player(guest)
      {:ok, guest_lv, _html} = live(guest_conn, ~p"/rooms/#{game.id}")

      {:ok, _dir_lv, dir_html} =
        guest_lv
        |> render_hook("leave_room", %{
          "player_id" => owner.id,
          "game_id" => Ecto.UUID.generate()
        })
        |> follow_redirect(guest_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."

      {:ok, lobby} = Games.get_room_lobby(Forka.Scope.for_player(owner), game.id)
      assert Enum.map(lobby.players, & &1.id) == [owner.id]
      assert lobby.owner_id == owner.id
    end

    test "REQ-04: stale guest unconfirmed leave after owner leaves prompts archival confirmation instead of archiving room",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      guest_scope = Forka.Scope.for_player(guest)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Corrida", max_players: 4})
      {:ok, :joined} = Games.join_room(guest_scope, game.id)

      guest_conn = conn |> log_in_player(guest)
      {:ok, guest_lv, _html} = live(guest_conn, ~p"/rooms/#{game.id}")

      refute has_element?(guest_lv, "#edit-room-settings")
      assert has_element?(guest_lv, "#leave-room-button")

      game_pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id
      guest_id = guest.id

      :ok = :sys.suspend(game_pid)

      {owner_task, guest_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          owner_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.leave_game(owner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :leave_game and elem(msg, 1) == owner_id

          guest_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              guest_lv |> element("#leave-room-button") |> render_click()
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, guest_msg}}, 1_000
          assert elem(guest_msg, 0) == :leave_game and elem(guest_msg, 1) == guest_id

          {owner_task, guest_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert :ok = Task.await(owner_task, 5_000)
      leave_html = Task.await(guest_task, 5_000)

      assert is_binary(leave_html)
      assert has_element?(guest_lv, "#leave-room-confirm", "Você é a última pessoa na sala.")
      assert has_element?(guest_lv, "#confirm-leave-room", "Sair e arquivar a sala")
      assert GameServer.whereis(game.id) == game_pid

      assert {:ok, lobby} = Games.get_room_lobby(guest_scope, game.id)
      assert lobby.status == :lobby
      assert lobby.owner_id == guest.id
      assert Enum.map(lobby.players, & &1.id) == [guest.id]

      ref = Process.monitor(game_pid)

      {:ok, _dir_lv, dir_html} =
        guest_lv
        |> element("#confirm-leave-room")
        |> render_click()
        |> follow_redirect(guest_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."
      assert_receive {:DOWN, ^ref, :process, ^game_pid, :normal}
      assert {:error, :game_archived} = Games.get_room_lobby(guest_scope, game.id)
    end

    test "REQ-04: owner confirming handoff when other player leaves re-prompts for archival instead of archiving",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      guest_scope = Forka.Scope.for_player(guest)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Handoff Corrida", max_players: 4})
      {:ok, :joined} = Games.join_room(guest_scope, game.id)

      owner_conn = conn |> log_in_player(owner)
      {:ok, owner_lv, _html} = live(owner_conn, ~p"/rooms/#{game.id}")

      owner_lv |> element("#leave-room-button") |> render_click()
      assert has_element?(owner_lv, "#leave-room-confirm", "A sala passa para bruno.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e passar a sala")

      game_pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id
      guest_id = guest.id

      :ok = :sys.suspend(game_pid)

      {guest_task, confirm_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          guest_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.leave_game(guest_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :leave_game and elem(msg, 1) == guest_id

          confirm_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              owner_lv |> element("#confirm-leave-room") |> render_click()
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, owner_msg}}, 1_000
          assert elem(owner_msg, 0) == :leave_game and elem(owner_msg, 1) == owner_id

          {guest_task, confirm_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert :ok = Task.await(guest_task, 5_000)
      confirm_html = Task.await(confirm_task, 5_000)

      assert is_binary(confirm_html)
      assert GameServer.whereis(game.id) == game_pid
      assert has_element?(owner_lv, "#leave-room-confirm", "Você é a última pessoa na sala.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e arquivar a sala")

      assert {:ok, lobby} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby.status == :lobby
      assert Enum.map(lobby.players, & &1.id) == [owner.id]

      ref = Process.monitor(game_pid)

      {:ok, _dir_lv, dir_html} =
        owner_lv
        |> element("#confirm-leave-room")
        |> render_click()
        |> follow_redirect(owner_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."
      assert_receive {:DOWN, ^ref, :process, ^game_pid, :normal}
    end

    test "REQ-04: owner confirming handoff to departed player when third player remains re-prompts with new target",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")
      owner_scope = Forka.Scope.for_player(owner)
      p2_scope = Forka.Scope.for_player(p2)
      p3_scope = Forka.Scope.for_player(p3)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Tres", max_players: 4})
      {:ok, :joined} = Games.join_room(p2_scope, game.id)
      {:ok, :joined} = Games.join_room(p3_scope, game.id)

      owner_conn = conn |> log_in_player(owner)
      {:ok, owner_lv, _html} = live(owner_conn, ~p"/rooms/#{game.id}")

      owner_lv |> element("#leave-room-button") |> render_click()
      assert has_element?(owner_lv, "#leave-room-confirm", "A sala passa para bruno.")

      game_pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id
      p2_id = p2.id

      :ok = :sys.suspend(game_pid)

      {p2_task, confirm_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          p2_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.leave_game(p2_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :leave_game and elem(msg, 1) == p2_id

          confirm_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              owner_lv |> element("#confirm-leave-room") |> render_click()
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, owner_msg}}, 1_000
          assert elem(owner_msg, 0) == :leave_game and elem(owner_msg, 1) == owner_id

          {p2_task, confirm_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert :ok = Task.await(p2_task, 5_000)
      confirm_html = Task.await(confirm_task, 5_000)

      assert is_binary(confirm_html)
      assert has_element?(owner_lv, "#leave-room-confirm", "A sala passa para caio.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e passar a sala")

      assert {:ok, lobby} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby.owner_id == owner.id

      {:ok, _dir_lv, dir_html} =
        owner_lv
        |> element("#confirm-leave-room")
        |> render_click()
        |> follow_redirect(owner_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."
      assert {:ok, after_lobby} = Games.get_room_lobby(p3_scope, game.id)
      assert after_lobby.owner_id == p3.id
    end

    test "REQ-04: owner confirming archive when another player joins re-prompts for handoff instead of leaving",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      guest_scope = Forka.Scope.for_player(guest)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Entra", max_players: 4})

      owner_conn = conn |> log_in_player(owner)
      {:ok, owner_lv, _html} = live(owner_conn, ~p"/rooms/#{game.id}")

      owner_lv |> element("#leave-room-button") |> render_click()
      assert has_element?(owner_lv, "#leave-room-confirm", "Você é a última pessoa na sala.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e arquivar a sala")

      game_pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id
      guest_id = guest.id

      :ok = :sys.suspend(game_pid)

      {join_task, confirm_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          join_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.join_room(guest_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :join_room and elem(msg, 1) == guest_id

          confirm_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              owner_lv |> element("#confirm-leave-room") |> render_click()
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, owner_msg}}, 1_000
          assert elem(owner_msg, 0) == :leave_game and elem(owner_msg, 1) == owner_id

          {join_task, confirm_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert {:ok, :joined} = Task.await(join_task, 5_000)
      confirm_html = Task.await(confirm_task, 5_000)

      assert is_binary(confirm_html)
      assert has_element?(owner_lv, "#leave-room-confirm", "A sala passa para bruno.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e passar a sala")

      assert {:ok, lobby} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby.owner_id == owner.id
      assert Enum.map(lobby.players, & &1.id) == [owner.id, guest.id]

      {:ok, _dir_lv, dir_html} =
        owner_lv
        |> element("#confirm-leave-room")
        |> render_click()
        |> follow_redirect(owner_conn, ~p"/")

      assert dir_html =~ "Você saiu da sala."
      assert {:ok, after_lobby} = Games.get_room_lobby(guest_scope, game.id)
      assert after_lobby.owner_id == guest.id
    end

    test "REQ-04: stale in-flight handoff confirmation arriving after LiveView PubSub update re-prompts for archival",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      guest_scope = Forka.Scope.for_player(guest)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala PubSub Race", max_players: 4})
      {:ok, :joined} = Games.join_room(guest_scope, game.id)

      owner_conn = conn |> log_in_player(owner)
      {:ok, owner_lv, _html} = live(owner_conn, ~p"/rooms/#{game.id}")

      owner_lv |> element("#leave-room-button") |> render_click()
      assert has_element?(owner_lv, "#leave-room-confirm", "A sala passa para bruno.")

      assert :ok = Games.leave_game(guest_scope, game.id)
      # Simulate browser click dispatched before LiveView DOM patch arrived
      render_hook(owner_lv, "confirm_leave_room", %{
        "consequence" => "handoff",
        "target_id" => guest.id
      })

      assert has_element?(owner_lv, "#leave-room-confirm", "Você é a última pessoa na sala.")
      assert has_element?(owner_lv, "#confirm-leave-room", "Sair e arquivar a sala")
      assert {:ok, lobby} = Games.get_room_lobby(owner_scope, game.id)
      assert lobby.status == :lobby
    end
  end

  describe "manual ownership transfer and stale target handling" do
    test "UI-02: owner confirms transfer via sheet and switches edit, transfer, badge, waiting status, notice, and directory live across all clients",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      target = insert(:player, username: "bruno")
      third = insert(:player, username: "caio")
      insert_list(6, :word)

      {:ok, game} = Games.create_game(owner.id, %{name: "Noite de palavras", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(target), game.id)
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(third), game.id)

      {:ok, owner_lv, _} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      {:ok, target_lv, _} = build_conn() |> log_in_player(target) |> live(~p"/rooms/#{game.id}")
      {:ok, third_lv, _} = build_conn() |> log_in_player(third) |> live(~p"/rooms/#{game.id}")
      {:ok, dir_lv, _} = build_conn() |> live(~p"/")
      _ = render_async(dir_lv)

      assert visible_text(render(dir_lv)) =~ "de lia"
      assert has_element?(owner_lv, "#transfer-ownership-#{target.id}", "Passar a posse")
      assert has_element?(owner_lv, "#transfer-ownership-mobile-#{target.id}")
      refute has_element?(owner_lv, "#transfer-ownership-#{owner.id}")
      refute has_element?(target_lv, "#transfer-ownership-#{owner.id}")
      refute has_element?(target_lv, "#edit-room-settings")

      # Open sheet from desktop button, verify gender-neutral copy, cancel keeps owner unchanged
      owner_lv |> element("#transfer-ownership-#{target.id}") |> render_click()
      assert has_element?(owner_lv, "#transfer-ownership-sheet", "Passar a sala para bruno?")

      assert has_element?(
               owner_lv,
               ~s|#transfer-ownership-sheet [role="dialog"][aria-describedby="transfer-ownership-sheet-description"]|
             )

      assert has_element?(
               owner_lv,
               "#transfer-ownership-sheet-description",
               "bruno passa a mudar as configurações e a começar a partida. Você continua na sala como participante."
             )

      assert has_element?(owner_lv, "#confirm-transfer-ownership", "Passar a posse")
      assert has_element?(owner_lv, "#cancel-transfer-ownership", "Cancelar")

      owner_lv |> element("#cancel-transfer-ownership") |> render_click()
      refute has_element?(owner_lv, "#transfer-ownership-sheet")
      assert has_element?(owner_lv, "#edit-room-settings")

      # Open sheet from mobile options button and confirm
      owner_lv |> element("#transfer-ownership-mobile-#{target.id}") |> render_click()
      assert has_element?(owner_lv, "#transfer-ownership-sheet", "Passar a sala para bruno?")

      owner_lv |> element("#confirm-transfer-ownership") |> render_click()
      refute has_element?(owner_lv, "#transfer-ownership-sheet")

      # Former owner loses edit/transfer controls and sees new owner state
      refute has_element?(owner_lv, "#edit-room-settings")
      refute has_element?(owner_lv, "#transfer-ownership-#{target.id}")
      refute has_element?(owner_lv, "#transfer-ownership-#{third.id}")
      assert has_element?(owner_lv, "#room-waiting-status", "Esperando bruno começar")
      assert has_element?(owner_lv, "#room-lobby-notice", "Agora bruno comanda a sala.")

      assert visible_text(element(owner_lv, "#room-lobby-player-#{target.id}") |> render()) =~
               "Anfitrião"

      refute visible_text(element(owner_lv, "#room-lobby-player-#{owner.id}") |> render()) =~
               "Anfitrião"

      # New owner gains edit and transfer controls immediately
      assert has_element?(target_lv, ~s|#edit-room-settings[href="/rooms/#{game.id}/settings"]|)
      assert has_element?(target_lv, "#transfer-ownership-#{owner.id}", "Passar a posse")
      assert has_element?(target_lv, "#transfer-ownership-#{third.id}", "Passar a posse")
      refute has_element?(target_lv, "#transfer-ownership-#{target.id}")
      assert has_element?(target_lv, "#room-lobby-notice", "Agora você comanda a sala.")
      assert has_element?(target_lv, "#room-waiting-status", "Sala pronta com 3 jogadores")

      # Third participant sees updated badge, waiting status, and notice
      refute has_element?(third_lv, "#edit-room-settings")
      refute has_element?(third_lv, "#transfer-ownership-#{owner.id}")
      assert has_element?(third_lv, "#room-waiting-status", "Esperando bruno começar")
      assert has_element?(third_lv, "#room-lobby-notice", "Agora bruno comanda a sala.")

      # Live directory reflects the new owner
      assert visible_text(render(dir_lv)) =~ "de bruno"
    end

    test "STALE-02: rejects forged non-owner and self-target transfer events", %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Segura", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(guest), game.id)

      {:ok, owner_lv, _} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      {:ok, guest_lv, _} = build_conn() |> log_in_player(guest) |> live(~p"/rooms/#{game.id}")

      # Non-owner forged events cannot open sheet or transfer ownership
      render_hook(guest_lv, "open_transfer_sheet", %{"player_id" => owner.id})
      refute has_element?(guest_lv, "#transfer-ownership-sheet")

      render_hook(guest_lv, "confirm_transfer_ownership", %{"player_id" => guest.id})

      assert has_element?(
               guest_lv,
               "#room-lobby-notice",
               "Apenas quem comanda a sala pode passar a posse."
             )

      # Owner forged self-target rejected cleanly
      render_hook(owner_lv, "open_transfer_sheet", %{"player_id" => owner.id})
      refute has_element?(owner_lv, "#transfer-ownership-sheet")

      render_hook(owner_lv, "confirm_transfer_ownership", %{"player_id" => owner.id})
      assert has_element?(owner_lv, "#room-lobby-notice", "Você já comanda esta sala.")

      {:ok, lobby} = Games.get_room_lobby(Forka.Scope.for_player(owner), game.id)
      assert lobby.owner_id == owner.id
    end

    test "STALE-02: closes sheet with notice when chosen target leaves while sheet is open or before confirm",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      target = insert(:player, username: "bruno")
      third = insert(:player, username: "caio")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Saiu", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(target), game.id)
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(third), game.id)

      {:ok, owner_lv, _} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")

      # Case 1: target leaves while sheet is open -> PubSub closes sheet and says so
      owner_lv |> element("#transfer-ownership-#{target.id}") |> render_click()
      assert has_element?(owner_lv, "#transfer-ownership-sheet", "Passar a sala para bruno?")

      assert :ok = Games.leave_game(Forka.Scope.for_player(target), game.id)
      _ = render(owner_lv)

      refute has_element?(owner_lv, "#transfer-ownership-sheet")
      assert has_element?(owner_lv, "#room-lobby-notice", "bruno saiu da sala.")

      # Case 2: in-flight confirm for a departed player arriving after PubSub -> closes with notice
      render_hook(owner_lv, "confirm_transfer_ownership", %{"player_id" => target.id})
      assert has_element?(owner_lv, "#room-lobby-notice", "Esse jogador não está mais na sala.")

      # Case 3: owner loses ownership from another session while sheet is open -> sheet closes with notice
      owner_lv |> element("#transfer-ownership-#{third.id}") |> render_click()
      assert has_element?(owner_lv, "#transfer-ownership-sheet", "Passar a sala para caio?")

      assert :ok = Games.transfer_ownership(Forka.Scope.for_player(owner), game.id, third.id)
      _ = render(owner_lv)

      refute has_element?(owner_lv, "#transfer-ownership-sheet")
      assert has_element?(owner_lv, "#room-lobby-notice", "Agora caio comanda a sala.")
    end

    test "STALE-02: confirm raced behind start_game does not transfer during match and redirects to match; confirm raced behind archive redirects to directory",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      target = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      insert_list(4, :word)

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Corrida Start", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(target), game.id)

      owner_conn = conn |> log_in_player(owner)
      {:ok, owner_lv, _} = live(owner_conn, ~p"/rooms/#{game.id}")
      owner_lv |> element("#transfer-ownership-#{target.id}") |> render_click()
      assert has_element?(owner_lv, "#transfer-ownership-sheet")

      game_pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)
      owner_id = owner.id

      :ok = :sys.suspend(game_pid)

      {start_task, confirm_task} =
        try do
          :erlang.trace(game_pid, true, [:receive])

          start_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.start_game(owner_scope, game.id)
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :start_game and elem(msg, 1) == owner_id

          confirm_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              owner_lv |> element("#confirm-transfer-ownership") |> render_click()
            end)

          assert_receive {:trace, ^game_pid, :receive, {:"$gen_call", _, transfer_msg}}, 1_000

          assert elem(transfer_msg, 0) == :transfer_ownership and
                   elem(transfer_msg, 1) == owner_id

          {start_task, confirm_task}
        after
          :erlang.trace(game_pid, false, [:receive])
          :sys.resume(game_pid)
        end

      assert :ok = Task.await(start_task, 5_000)
      assert {:error, {:live_redirect, %{to: redirect_to}}} = Task.await(confirm_task, 5_000)
      assert redirect_to == ~p"/rooms/#{game.id}/match"
      assert Games.get_game_summary(game.id).owner.id == owner.id

      # Second room: confirm raced behind archive_game redirects to directory with unified flash
      {:ok, archived_game} =
        Games.create_game(owner.id, %{name: "Sala Corrida Arch", max_players: 4})

      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(target), archived_game.id)

      owner_conn2 = build_conn() |> log_in_player(owner)
      {:ok, lv2, _} = live(owner_conn2, ~p"/rooms/#{archived_game.id}")
      lv2 |> element("#transfer-ownership-#{target.id}") |> render_click()

      arch_pid = GameServer.whereis(archived_game.id)
      arch_ref = Process.monitor(arch_pid)
      :ok = :sys.suspend(arch_pid)

      {arch_task, confirm_arch_task} =
        try do
          :erlang.trace(arch_pid, true, [:receive])

          arch_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Games.archive_game(owner_scope, archived_game.id)
            end)

          assert_receive {:trace, ^arch_pid, :receive, {:"$gen_call", _, msg}}, 1_000
          assert elem(msg, 0) == :archive_game

          confirm_arch_task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              lv2 |> element("#confirm-transfer-ownership") |> render_click()
            end)

          assert_receive {:trace, ^arch_pid, :receive, {:"$gen_call", _, tmsg}}, 1_000
          assert elem(tmsg, 0) == :transfer_ownership

          {arch_task, confirm_arch_task}
        after
          :erlang.trace(arch_pid, false, [:receive])
          :sys.resume(arch_pid)
        end

      assert :ok = Task.await(arch_task, 5_000)
      assert_receive {:DOWN, ^arch_ref, :process, ^arch_pid, :normal}

      {:ok, _dir_lv, dir_html} =
        confirm_arch_task
        |> Task.await(5_000)
        |> follow_redirect(owner_conn2, ~p"/")

      assert dir_html =~ "Esta sala foi arquivada."
    end

    test "OWN-05: opening an ownerless room in RoomLive promotes next seat or redirects archived when empty",
         %{conn: conn} do
      owner = insert(:player, username: "lia")
      member = insert(:player, username: "bruno")

      {:ok, shared} = Games.create_game(owner.id, %{name: "Sala Orfa Membro", max_players: 4})
      {:ok, :joined} = Games.join_room(Forka.Scope.for_player(member), shared.id)
      Forka.Repo.delete!(owner)

      {:ok, lv, _html} = conn |> log_in_player(member) |> live(~p"/rooms/#{shared.id}")
      assert has_element?(lv, ~s|#edit-room-settings[href="/rooms/#{shared.id}/settings"]|)

      assert visible_text(element(lv, "#room-lobby-player-#{member.id}") |> render()) =~
               "Anfitrião"

      solo_owner = insert(:player, username: "caio")
      {:ok, solo} = Games.create_game(solo_owner.id, %{name: "Sala Orfa Vazia", max_players: 4})
      Forka.Repo.delete!(solo_owner)

      assert {:error,
              {:live_redirect, %{to: "/", flash: %{"error" => "Esta sala foi arquivada."}}}} =
               build_conn() |> log_in_player(member) |> live(~p"/rooms/#{solo.id}")
    end
  end
end
