defmodule ForkaWeb.Admin.GameLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Forka.Games.Core
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Game
  alias Forka.Repo

  setup :register_and_log_in_admin

  @tag audit_f10: true
  test "F-10 the archived filter excludes new lobbies and includes a game once archived", %{
    conn: conn
  } do
    owner = insert(:player)
    {:ok, view, _html} = live(conn, ~p"/admin/games?filters[status]=archived")

    {:ok, game} = Repository.insert_game(owner.id, %{name: "Incoming archive", max_players: 2})
    _ = :sys.get_state(view.pid)
    refute has_element?(view, "#row-item-#{game.id}")

    {:ok, state} = Repository.get_game_state(game.id)
    {:ok, archived} = Core.archive_game(state)
    assert {:ok, %{status: :archived}} = Repository.save_game_state(archived)
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#row-item-#{game.id}")
  end

  @tag audit_f10: true
  test "F-10 a game leaves the lobby filter when archived", %{conn: conn} do
    owner = insert(:player)
    {:ok, game} = Repository.insert_game(owner.id, %{name: "Outgoing lobby", max_players: 2})
    {:ok, view, _html} = live(conn, ~p"/admin/games?filters[status]=lobby")
    assert has_element?(view, "#row-item-#{game.id}")

    {:ok, state} = Repository.get_game_state(game.id)
    {:ok, archived} = Core.archive_game(state)
    assert {:ok, %{status: :archived}} = Repository.save_game_state(archived)
    _ = :sys.get_state(view.pid)
    refute has_element?(view, "#row-item-#{game.id}")
  end

  @tag audit_f10: true
  test "F-10 an insertion outside the active page leaves the visible page intact", %{conn: conn} do
    owner = insert(:player)

    rooms =
      for number <- 1..16 do
        suffix = number |> Integer.to_string() |> String.pad_leading(2, "0")
        {:ok, room} = Repository.insert_game(owner.id, %{name: "Room #{suffix}", max_players: 2})
        room
      end

    [first | _] = rooms
    [last, previous | _] = Enum.reverse(rooms)

    path = ~p"/admin/games?order_by=name&order_direction=asc&per_page=15&page=2"
    {:ok, view, _html} = live(conn, path)
    assert has_element?(view, "#row-item-#{last.id}")
    refute has_element?(view, "#row-item-#{first.id}")

    {:ok, incoming} = Repository.insert_game(owner.id, %{name: "Room 00", max_players: 2})
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#row-item-#{previous.id}")
    assert has_element?(view, "#row-item-#{last.id}")
    refute has_element?(view, "#row-item-#{incoming.id}")
  end

  test "a renamed game refreshes pagination and drops the selection it displaces", %{conn: conn} do
    owner = insert(:player)

    for number <- 1..14 do
      suffix = number |> Integer.to_string() |> String.pad_leading(2, "0")
      insert(:game, name: "Room #{suffix}", owner: owner)
    end

    selected = insert(:game, name: "Room 15", owner: owner, status: :archived)
    incoming = insert(:game, name: "Room 16", owner: owner)

    path = ~p"/admin/games?order_by=name&order_direction=asc&per_page=15&page=1"
    {:ok, view, _html} = live(conn, path)

    bulk_delete =
      ~s|button[phx-click="item-action"][phx-value-action-key="delete"]:not([phx-value-item-id])|

    assert has_element?(view, "#row-item-#{selected.id}")
    refute has_element?(view, "#row-item-#{incoming.id}")

    view |> element("#select-input-#{selected.id}") |> render_click()
    view |> element(bulk_delete) |> render_click()
    assert has_element?(view, "#action-confirm-modal")

    {:ok, state} = Repository.get_game_state(incoming.id)
    assert {:ok, _} = Repository.save_game_state(%{state | name: "Room 00"})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#row-item-#{incoming.id}")
    refute has_element?(view, "#row-item-#{selected.id}")
    refute has_element?(view, "#action-confirm-modal")
    refute has_element?(view, bulk_delete <> ":not([disabled])")
    assert Repo.get(Game, selected.id)
  end
end
