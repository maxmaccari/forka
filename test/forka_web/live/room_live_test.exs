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
end
