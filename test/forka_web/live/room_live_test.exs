defmodule ForkaWeb.RoomLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Forka.Games
  alias Forka.Games.GameServer

  describe "GET /salas/:id" do
    test "AC-05: redirects unauthenticated visitor to login", %{conn: conn} do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Privada", max_players: 4})

      assert {:error, {:redirect, %{to: "/players/log_in"}}} = live(conn, ~p"/salas/#{game.id}")
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

      {:ok, lv, html} = conn |> log_in_player(owner) |> live(~p"/salas/#{game.id}")
      text = visible_text(html)

      assert page_title(lv) =~ "Noite de palavras"
      assert text =~ "Noite de palavras"
      assert text =~ "1/6 jogadores"
      assert text =~ "Português"
      assert text =~ "Música"
      assert text =~ "lia"
      assert has_element?(lv, ~s|#edit-room-settings[href="/salas/#{game.id}/configuracoes"]|)
    end

    test "AC-05: renders room created without word_options using safe defaults", %{conn: conn} do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_game(owner.id, %{name: "Sem opções", max_players: 4})

      {:ok, _lv, html} = conn |> log_in_player(owner) |> live(~p"/salas/#{game.id}")
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

      {:ok, lv, html} = conn |> log_in_player(other) |> live(~p"/salas/#{game.id}")
      assert visible_text(html) =~ "Todas as categorias"
      refute has_element?(lv, "#edit-room-settings")
    end

    test "AC-05: hides owner settings link once the game is no longer in lobby", %{conn: conn} do
      owner = insert(:player, username: "lia")
      guest = insert(:player, username: "bruno")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala jogando", max_players: 4})
      :ok = Games.join_game(game.id, guest.id)
      insert(:word, text: "forka")
      :ok = Games.start_game(game.id)

      {:ok, lv, _html} = conn |> log_in_player(owner) |> live(~p"/salas/#{game.id}")
      refute has_element?(lv, "#edit-room-settings")
    end

    test "AC-05: redirects to directory with flash when room does not exist or ID is invalid",
         %{conn: conn} do
      player = insert(:player)
      missing_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Sala não encontrada."}}}} =
               conn |> log_in_player(player) |> live(~p"/salas/#{missing_id}")

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Sala não encontrada."}}}} =
               conn |> log_in_player(player) |> live(~p"/salas/not-a-uuid")
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
               conn |> log_in_player(owner) |> live(~p"/salas/#{game.id}")
    end

    test "AC-05: receives live room lobby updates after mounting", %{conn: conn} do
      owner = insert(:player, username: "lia")
      viewer = insert(:player, username: "bruno")
      owner_scope = Forka.Scope.for_player(owner)
      cat = insert(:category, name: "Cinema", language: "pt")

      {:ok, game} = Games.create_game(owner.id, %{name: "Sala Inicial", max_players: 4})

      {:ok, lv, _html} = conn |> log_in_player(viewer) |> live(~p"/salas/#{game.id}")

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
  end
end
