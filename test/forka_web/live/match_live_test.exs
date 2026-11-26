defmodule ForkaWeb.MatchLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Forka.Games
  alias Forka.Games.GameServer
  alias Forka.Scope

  defp started_room_fixture do
    owner = insert(:player, username: "lia")
    guest = insert(:player, username: "bruno")
    insert_list(4, :word)

    {:ok, game} = Games.create_game(owner.id, %{name: "Noite de palavras", max_players: 4})
    {:ok, :joined} = Games.join_room(Scope.for_player(guest), game.id)
    :ok = Games.start_game(Scope.for_player(owner), game.id)

    %{game: game, owner: owner, guest: guest}
  end

  describe "GET /rooms/:id/match" do
    test "REQ-08: redirects unauthenticated visitor to login", %{conn: conn} do
      %{game: game} = started_room_fixture()

      assert {:error, {:redirect, %{to: "/players/log_in"}}} =
               live(conn, ~p"/rooms/#{game.id}/match")
    end

    test "REQ-08: redirects signed-in non-participant to join page", %{conn: conn} do
      %{game: game} = started_room_fixture()
      outsider = insert(:player, username: "caio")

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               conn |> log_in_player(outsider) |> live(~p"/rooms/#{game.id}/match")

      assert redirect_to == ~p"/rooms/#{game.id}/join"
    end

    test "REQ-08: redirects seated participant back to lobby when match has not started", %{
      conn: conn
    } do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_game(owner.id, %{name: "Ainda no lobby", max_players: 4})

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}/match")

      assert redirect_to == ~p"/rooms/#{game.id}"
    end

    test "REQ-07: renders minimal placeholder match page for seated participants with no gameplay controls",
         %{conn: conn} do
      %{game: game, owner: owner, guest: guest} = started_room_fixture()

      for player <- [owner, guest] do
        {:ok, lv, html} =
          conn |> log_in_player(player) |> live(~p"/rooms/#{game.id}/match")

        text = visible_text(html)
        assert page_title(lv) =~ "Noite de palavras"
        assert has_element?(lv, "#match-placeholder")
        assert has_element?(lv, "#match-placeholder-card")
        assert text =~ "Noite de palavras"
        assert text =~ "Partida em andamento"
        assert text =~ "lia"
        assert text =~ "bruno"
        assert has_element?(lv, ~s|#match-back-to-rooms[href="/"]|)
        refute has_element?(lv, ~s|[data-keyboard]|)
      end
    end

    test "REQ-08: redirects to directory with flash for missing or archived rooms", %{conn: conn} do
      owner = insert(:player)
      missing_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Sala não encontrada."}}}} =
               conn |> log_in_player(owner) |> live(~p"/rooms/#{missing_id}/match")

      {:ok, game} = Games.create_game(owner.id, %{name: "Arquivada", max_players: 4})
      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)
      :ok = Games.archive_game(Scope.for_player(owner), game.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert {:error,
              {:live_redirect, %{to: "/", flash: %{"error" => "Esta sala foi arquivada."}}}} =
               conn |> log_in_player(owner) |> live(~p"/rooms/#{game.id}/match")
    end

    test "EDGE-03: redirects mounted participant to lobby on restart and to directory on archive",
         %{conn: conn} do
      %{game: game, owner: owner, guest: guest} = started_room_fixture()

      {:ok, lv, _html} =
        conn |> log_in_player(guest) |> live(~p"/rooms/#{game.id}/match")

      # Give up so game ends, then owner restarts -> guest returns to lobby
      :ok = Games.give_up_game(Scope.for_player(owner), game.id)
      :ok = Games.give_up_game(Scope.for_player(guest), game.id)
      :ok = Games.restart_game(Scope.for_player(owner), game.id)
      assert_redirect(lv, ~p"/rooms/#{game.id}")

      # Start again, end again, then archive -> mounted participant redirects to directory
      :ok = Games.start_game(Scope.for_player(owner), game.id)

      {:ok, lv2, _html} =
        conn |> log_in_player(guest) |> live(~p"/rooms/#{game.id}/match")

      :ok = Games.give_up_game(Scope.for_player(owner), game.id)
      :ok = Games.give_up_game(Scope.for_player(guest), game.id)
      :ok = Games.archive_game(Scope.for_player(owner), game.id)
      flash = assert_redirect(lv2, ~p"/")
      assert flash["error"] == "Esta sala foi arquivada."
    end
  end
end
