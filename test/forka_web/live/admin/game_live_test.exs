defmodule ForkaWeb.Admin.GameLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Forka.Games.Core
  alias Forka.Games.Repository

  setup :register_and_log_in_admin

  @tag audit_f10: true
  test "F-10 the archived filter excludes new lobbies and includes a game once archived", %{
    conn: conn
  } do
    owner = insert(:player)
    {:ok, view, _html} = live(conn, ~p"/admin/games?filters[status]=archived")

    {:ok, game} = Repository.insert_game(owner.id, %{name: "Incoming archive", max_players: 2})
    :sys.get_state(view.pid)
    refute render(view) =~ "Incoming archive"

    {:ok, state} = Repository.get_game_state(game.id)
    {:ok, archived} = Core.archive_game(state)
    assert {:ok, %{status: :archived}} = Repository.save_game_state(archived)
    :sys.get_state(view.pid)
    assert render(view) =~ "Incoming archive"
  end

  @tag audit_f10: true
  test "F-10 a game leaves the lobby filter when archived", %{conn: conn} do
    owner = insert(:player)
    {:ok, game} = Repository.insert_game(owner.id, %{name: "Outgoing lobby", max_players: 2})
    {:ok, view, html} = live(conn, ~p"/admin/games?filters[status]=lobby")
    assert html =~ "Outgoing lobby"

    {:ok, state} = Repository.get_game_state(game.id)
    {:ok, archived} = Core.archive_game(state)
    assert {:ok, %{status: :archived}} = Repository.save_game_state(archived)
    :sys.get_state(view.pid)
    refute render(view) =~ "Outgoing lobby"
  end

  @tag audit_f10: true
  test "F-10 an insertion outside the active page leaves the visible page intact", %{conn: conn} do
    owner = insert(:player)

    for number <- 1..16 do
      suffix = number |> Integer.to_string() |> String.pad_leading(2, "0")
      {:ok, _game} = Repository.insert_game(owner.id, %{name: "Room #{suffix}", max_players: 2})
    end

    path = ~p"/admin/games?order_by=name&order_direction=asc&per_page=15&page=2"
    {:ok, view, html} = live(conn, path)
    assert html =~ "Room 16"
    refute html =~ "Room 01"

    {:ok, _game} = Repository.insert_game(owner.id, %{name: "Room 00", max_players: 2})
    :sys.get_state(view.pid)
    html = render(view)
    assert html =~ "Room 15"
    assert html =~ "Room 16"
    refute html =~ "Room 00"
  end
end
