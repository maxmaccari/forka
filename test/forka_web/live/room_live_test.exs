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

      {:ok, lv, html} = conn |> log_in_player(other) |> live(~p"/rooms/#{game.id}")
      assert visible_text(html) =~ "Todas as categorias"
      refute has_element?(lv, "#edit-room-settings")
    end

    test "AC-05: hides owner settings link once the game is no longer in lobby", %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala jogando", max_players: 4})
      :ok = Games.join_game(game.id, guest.id)
      insert_list(4, :word)
      :ok = Games.start_game(game.id)

      {:ok, lv, _html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      refute has_element?(lv, "#edit-room-settings")
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
      :ok = Games.archive_game(game.id)
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

      {:ok, lv, _html} = conn |> log_in_player(viewer) |> live(~p"/rooms/#{game.id}")

      :ok =
        Games.update_room_settings(owner_scope, game.id, %{
          name: "Sala Renovada",
          max_players: 6,
          word_options: %{language: "pt", category_ids: [cat.id]}
        })

      text = lv |> render() |> visible_text()
      assert text =~ "Sala Renovada"
      assert text =~ "1/6 jogadores"
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

      :ok = Games.join_game(game.id, p2.id)

      {:ok, lv, html} = conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}")
      assert visible_text(html) =~ "2 de 6 · 4 palavras (2 por jogador)"
      refute has_element?(lv, "#room-word-availability-alert")

      # 3rd player joins -> required rises to 6 while pool has 4 -> alert appears with owner link
      :ok = Games.join_game(game.id, p3.id)
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
      :ok = Games.leave_game(game.id, p3.id)
      left_text = lv |> render() |> visible_text()
      assert left_text =~ "2 de 6 · 4 palavras (2 por jogador)"
      refute has_element?(lv, "#room-word-availability-alert")

      # 3rd player rejoins, then owner broadens categories -> alert disappears
      :ok = Games.join_game(game.id, p3.id)
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

      {:ok, lv, html} = conn |> log_in_player(viewer) |> live(~p"/rooms/#{game.id}")
      assert has_element?(lv, "#room-word-availability-alert")
      assert visible_text(html) =~ "0 palavras válidas"
      refute has_element?(lv, "#broaden-word-selection")
    end
  end
end
