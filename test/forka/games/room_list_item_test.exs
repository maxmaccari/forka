defmodule Forka.Games.RoomListItemTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Forka.Games.RoomListItem
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.WordOptions

  describe "visible_status?/1" do
    test "AC-02: treats lobby, playing, finished, and game_over as visible and hides archived" do
      assert RoomListItem.visible_status?(:lobby)
      assert RoomListItem.visible_status?(:playing)
      assert RoomListItem.visible_status?(:finished)
      assert RoomListItem.visible_status?(:game_over)
      refute RoomListItem.visible_status?(:archived)
    end
  end

  describe "availability_state/1 and joinable?/1" do
    test "AC-02: classifies open lobby, full lobby, playing, and finished/game_over rooms" do
      open_room = %RoomListItem{
        id: Ecto.UUID.generate(),
        name: "Noite de palavras",
        status: :lobby,
        player_count: 2,
        max_players: 4
      }

      full_room = %{open_room | player_count: 4}
      playing_room = %{open_room | status: :playing}
      finished_room = %{open_room | status: :finished}
      game_over_room = %{open_room | status: :game_over}

      assert RoomListItem.availability_state(open_room) == :open
      assert RoomListItem.joinable?(open_room)

      assert RoomListItem.availability_state(full_room) == :full
      refute RoomListItem.joinable?(full_room)

      assert RoomListItem.availability_state(playing_room) == :playing
      refute RoomListItem.joinable?(playing_room)

      assert RoomListItem.availability_state(finished_room) == :ended
      refute RoomListItem.joinable?(finished_room)

      assert RoomListItem.availability_state(game_over_room) == :ended
      refute RoomListItem.joinable?(game_over_room)
    end

    property "EDGE-01: a room is joinable if and only if it is in lobby with free capacity" do
      check all status <- member_of([:lobby, :playing, :finished, :game_over, :archived]),
                max_players <- integer(2..6),
                player_count <- integer(0..8) do
        item = %RoomListItem{
          id: "room-1",
          name: "Sala",
          status: status,
          player_count: player_count,
          max_players: max_players
        }

        expected_joinable? = status == :lobby and player_count < max_players
        assert RoomListItem.joinable?(item) == expected_joinable?

        if expected_joinable? do
          assert RoomListItem.availability_state(item) == :open
        else
          refute RoomListItem.availability_state(item) == :open
        end
      end
    end
  end

  describe "from_game/4 and from_event/1" do
    test "AC-02: projects a Game schema and category map into a RoomListItem" do
      cat_a = Ecto.UUID.generate()
      cat_b = Ecto.UUID.generate()
      missing_cat = Ecto.UUID.generate()

      game = %Game{
        id: Ecto.UUID.generate(),
        name: "Família Souza",
        status: :lobby,
        max_players: 6,
        word_options: %WordOptions{language: "pt", category_ids: [cat_b, cat_a, missing_cat]}
      }

      categories_by_id = %{cat_a => "Cinema", cat_b => "Música"}
      item = RoomListItem.from_game(game, 3, "bruno", categories_by_id)

      assert item == %RoomListItem{
               id: game.id,
               name: "Família Souza",
               status: :lobby,
               player_count: 3,
               max_players: 6,
               owner_username: "bruno",
               language: "pt",
               category_names: ["Cinema", "Música"]
             }
    end

    test "EDGE-01: defaults nil word_options and nil owner gracefully" do
      game = %Game{
        id: Ecto.UUID.generate(),
        name: "Sala sem dono",
        status: :lobby,
        max_players: 4,
        word_options: nil
      }

      item = RoomListItem.from_game(game, 0, nil, %{})

      assert item.owner_username == nil
      assert item.language == "en"
      assert item.category_names == []
    end

    test "AC-02: projects a game_list_updated payload into a RoomListItem" do
      id = Ecto.UUID.generate()

      payload = %{
        id: id,
        name: "Turma do RPG",
        status: :playing,
        player_count: 3,
        max_players: 6,
        owner_username: "caio",
        language: "pt",
        category_names: ["Jogos", "Música"]
      }

      assert RoomListItem.from_event(payload) == %RoomListItem{
               id: id,
               name: "Turma do RPG",
               status: :playing,
               player_count: 3,
               max_players: 6,
               owner_username: "caio",
               language: "pt",
               category_names: ["Jogos", "Música"]
             }
    end
  end
end
