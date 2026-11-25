defmodule Forka.Games.CoreTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Forka.Games.Core
  alias Forka.Games.RoomSettings
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.WordOptions

  import Forka.TestHelpers

  setup do
    owner = build_games_player("Owner")

    %{owner: owner}
  end

  describe "new/2" do
    test "creates a new game with valid parameters", %{owner: owner} do
      name = "Test Game"
      max_players = 4
      game = Core.new(owner, name, max_players)

      assert game.owner == owner
      assert game.name == name
      assert game.max_players == max_players
      assert game.status == :lobby
      assert game.game_words == %{}
      assert game.game_players == %{}
      assert game.current_game_word_index == nil
      assert game.current_game_player_index == nil
      assert game.tick == 0
      assert game.events == []
    end
  end

  describe "join_game/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player = build_games_player("Player 1")
      {:ok, game: game, player: player}
    end

    test "adds player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Core.join_game(game, player)

      assert map_size(updated_game.game_players) == 1

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [%{type: :player_joined, payload: %{player_id: player.id}}])

      assert %{0 => game_player} = updated_game.game_players

      assert game_player.player.id == player.id
      assert game_player.player.username == player.username
      assert game_player.status == :alive
      assert game_player.lives == 6
      assert game_player.score == 0
    end

    test "adds players in sequential order", %{game: game} do
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      player3 = build_games_player("Player 3")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_player2} = Core.join_game(game_with_player1, player2)
      {:ok, game_with_player3} = Core.join_game(game_with_player2, player3)

      assert map_size(game_with_player3.game_players) == 3
      assert %{0 => %{player: %{username: "Player 1"}}} = game_with_player3.game_players
      assert %{1 => %{player: %{username: "Player 2"}}} = game_with_player3.game_players
      assert %{2 => %{player: %{username: "Player 3"}}} = game_with_player3.game_players
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Core.join_game(game_started, player)
    end

    test "returns error when max players reached", %{game: game, player: player} do
      game = %{game | max_players: 1}
      {:ok, game_with_player} = Core.join_game(game, player)

      player2 = build_games_player("Player 2")
      assert {:error, :maximum_players} = Core.join_game(game_with_player, player2)
    end

    test "returns error when game is archived", %{game: game, player: player} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Core.join_game(game_archived, player)
    end
  end

  describe "leave_game/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player = build_games_player("Player 1")
      {:ok, game_with_player} = Core.join_game(game, player)
      {:ok, game: game_with_player, player: player}
    end

    test "removes player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Core.leave_game(game, player.id)
      assert map_size(updated_game.game_players) == 0

      assert updated_game.tick == game.tick + 1

      assert assert_last_events(updated_game, [
               %{type: :player_left, payload: %{player_id: player.id}}
             ])
    end

    test "reindexes players after removal", %{game: game_with_player1} do
      player2 = build_games_player("Player 2")
      player3 = build_games_player("Player 3")

      {:ok, game_with_player2} = Core.join_game(game_with_player1, player2)
      {:ok, game_with_player3} = Core.join_game(game_with_player2, player3)

      {:ok, updated_game} = Core.leave_game(game_with_player3, player2.id)

      # Check that player3 is now at index 1 (second position)
      assert map_size(updated_game.game_players) == 2
      assert %{0 => %{player: %{username: "Player 1"}}} = updated_game.game_players
      assert %{1 => %{player: %{username: "Player 3"}}} = updated_game.game_players
    end

    test "returns unchanged game when removing player that doesn't exist", %{game: game} do
      unknown_player = build_games_player("Unknown")
      assert {:ok, ^game} = Core.leave_game(game, unknown_player.id)
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Core.leave_game(game_started, player.id)
    end

    test "returns error when game is archived", %{game: game, player: player} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Core.leave_game(game_archived, player.id)
    end
  end

  describe "set_words/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)

      words = [
        Word.new("cat", "animals", "Meows"),
        Word.new("dog", "animals", "Barks")
      ]

      {:ok, game: game, words: words}
    end

    test "sets words successfully", %{game: game, words: words} do
      assert updated_game = Core.set_words(game, words)
      assert map_size(updated_game.game_words) == 2

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [%{type: :words_set, payload: %{count: 2}}])

      Enum.each(updated_game.game_words, fn {_idx, game_word} ->
        assert %GameWord{} = game_word
        assert game_word.guesses == []
        assert game_word.finished_by_id == nil
      end)
    end

    test "removes duplicate words", %{game: game, words: words} do
      duplicate_words = words ++ [List.first(words)]
      updated_game = Core.set_words(game, duplicate_words)
      assert map_size(updated_game.game_words) == 2
    end

    test "does not set words when game is not in lobby state", %{game: game, words: words} do
      game_playing = %{game | status: :playing}
      assert ^game_playing = Core.set_words(game_playing, words)

      game_archived = %{game | status: :archived}
      assert ^game_archived = Core.set_words(game_archived, words)
    end
  end

  describe "shuffle_players/1" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 10)

      # Add multiple players to ensure we have enough for shuffling
      players = for i <- 1..10, do: build_games_player("Player #{i}")

      # Add all players to the game
      game_with_players =
        Enum.reduce(players, game, fn player, acc_game ->
          {:ok, updated_game} = Core.join_game(acc_game, player)
          updated_game
        end)

      {:ok, game: game_with_players, players: players}
    end

    test "shuffles players only in lobby state", %{game: game} do
      # Test in lobby state
      shuffled_game = Core.shuffle_players(game)
      assert shuffled_game.status == :lobby

      assert shuffled_game.tick == game.tick + 1
      assert_last_events(shuffled_game, [%{type: :players_shuffled}])

      # The player IDs should be the same, but potentially in different order
      original_player_ids =
        game.game_players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      shuffled_player_ids =
        shuffled_game.game_players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      assert original_player_ids == shuffled_player_ids

      # Verify player indices are sequential and start from 0
      player_indices = shuffled_game.game_players |> Map.keys() |> Enum.sort()
      assert player_indices == Enum.to_list(0..(map_size(shuffled_game.game_players) - 1))

      # Test in playing state - should not shuffle
      game_playing = %{game | status: :playing}
      assert ^game_playing = Core.shuffle_players(game_playing)

      # Test in archived state - should not shuffle
      game_archived = %{game | status: :archived}
      assert ^game_archived = Core.shuffle_players(game_archived)
    end

    test "maintains consistent state after shuffle", %{game: game} do
      shuffled_game = Core.shuffle_players(game)

      # Player count should remain the same
      assert map_size(game.game_players) == map_size(shuffled_game.game_players)

      # Each player should maintain their properties
      Enum.each(shuffled_game.game_players, fn {_idx, game_player} ->
        assert game_player.status == :alive
        assert game_player.lives == 6
        assert game_player.score == 0
      end)
    end
  end

  describe "start_game/1" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      word = Word.new("cat", "Animals", "Meows")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
      game_with_words = Core.set_words(game_with_players, [word])

      {:ok, game: game_with_words}
    end

    test "initializes game successfully when ready", %{game: game} do
      {:ok, initialized_game} = Core.start_game(game)

      assert initialized_game.status == :playing
      assert initialized_game.current_game_word_index == 0
      assert initialized_game.current_game_player_index == 0
      assert map_size(initialized_game.game_players) == 2
      assert map_size(initialized_game.game_words) == 1

      assert initialized_game.tick == game.tick + 1
      assert_last_events(initialized_game, [%{type: :game_started}])
    end

    test "returns error when game not in lobby", %{game: game} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_initialized} = Core.start_game(game_started)
    end

    test "returns error when not enough players", %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player = build_games_player("Player 1")
      {:ok, game_with_player} = Core.join_game(game, player)

      assert {:error, :game_not_ready} = Core.start_game(game_with_player)
    end

    test "returns error when game is archived", %{game: game} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Core.start_game(game_archived)
    end
  end

  describe "restart_game/1" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      word = Word.new("cat", "Animals", "Meows")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
      game_with_words = Core.set_words(game_with_players, [word])

      {:ok, initialized_game} = Core.start_game(game_with_words)

      # Create a finished game with some player state changes
      finished_game = %{initialized_game | status: :finished}

      # Simulate a player with reduced lives and dead status
      updated_players =
        Map.update!(
          finished_game.game_players,
          0,
          fn player -> %{player | lives: 0, status: :dead} end
        )

      finished_game_with_player_changes = %{finished_game | game_players: updated_players}

      {:ok,
       game_lobby: game_with_words,
       game_playing: initialized_game,
       game_finished: finished_game_with_player_changes}
    end

    test "restarts game successfully when in finished status", %{game_finished: game} do
      assert {:ok, restarted_game} = Core.restart_game(game)

      # Check that game is back in lobby state
      assert restarted_game.status == :lobby

      # Check that player lives and status are reset
      Enum.each(restarted_game.game_players, fn {_idx, player} ->
        assert player.lives == 6
        assert player.status == :alive
      end)

      # Check that game state is properly reset
      assert restarted_game.current_game_player_index == nil
      assert restarted_game.current_game_word_index == nil
      assert restarted_game.game_words == %{}

      assert restarted_game.tick == game.tick + 1
      assert_last_events(restarted_game, [%{type: :game_restarted}])
    end

    @tag audit_f08: true
    test "F-08 restarting a finished round resets all player scores", %{game_finished: game} do
      game = %{
        game
        | game_players:
            game.game_players
            |> Map.update!(0, &%{&1 | score: 70})
            |> Map.update!(1, &%{&1 | score: 30})
      }

      assert {:ok, restarted} = Core.restart_game(game)
      assert restarted.status == :lobby
      assert %{score: 0, lives: 6, status: :alive} = restarted.game_players[0]
      assert %{score: 0, lives: 6, status: :alive} = restarted.game_players[1]
    end

    test "restarts game successfully when in lobby status", %{game_lobby: game} do
      assert {:ok, restarted_game} = Core.restart_game(game)
      assert restarted_game.status == :lobby
    end

    test "returns error when game is in playing status", %{game_playing: game} do
      assert {:error, :game_in_progress} = Core.restart_game(game)
    end

    test "returns error when game is archived", %{game_finished: game} do
      # First archive the game
      {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived

      # Then try to restart it
      assert {:error, :game_archived} = Core.restart_game(archived_game)
    end
  end

  describe "archive_game/1" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      word = Word.new("cat", "Animals", "Meows")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
      game_with_words = Core.set_words(game_with_players, [word])

      {:ok, initialized_game} = Core.start_game(game_with_words)

      # Create a finished game
      finished_game = %{initialized_game | status: :finished}

      {:ok,
       game_lobby: game_with_words, game_playing: initialized_game, game_finished: finished_game}
    end

    test "archives game successfully when in lobby status", %{game_lobby: game} do
      assert {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived

      assert archived_game.tick == game.tick + 1
      assert_last_events(archived_game, [%{type: :game_archived}])
    end

    test "archives game successfully when in finished status", %{game_finished: game} do
      assert {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived
    end

    test "returns error when game is in playing status", %{game_playing: game} do
      assert {:error, :game_in_progress} = Core.archive_game(game)
    end

    test "cannot modify an archived game", %{game_lobby: game} do
      # First archive the game
      {:ok, archived_game} = Core.archive_game(game)
      assert archived_game.status == :archived

      # Verify that archived games cannot be modified
      player = build_games_player("New Player")
      word = Word.new("dog", "Animals", "Barks")

      # Test various operations on archived game
      assert {:error, :game_archived} = Core.join_game(archived_game, player)
      assert {:error, :game_archived} = Core.leave_game(archived_game, "any_player_id")
      assert archived_game == Core.set_words(archived_game, [word])
      assert archived_game == Core.shuffle_players(archived_game)
      assert {:error, :game_archived} = Core.start_game(archived_game)
      assert {:error, :game_archived} = Core.guess(archived_game, "any_player_id", "a")
      assert {:error, :game_archived} = Core.give_up_game(archived_game, "any_player_id")
    end
  end

  describe "transfer_ownership_to_player/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")

      {:ok, game_with_player1} = Core.join_game(game, player1)
      {:ok, game_with_players} = Core.join_game(game_with_player1, player2)

      {:ok, game: game_with_players, player1: player1, player2: player2, owner: owner}
    end

    test "transfers ownership successfully", %{game: game, player1: player1} do
      {:ok, updated_game} = Core.transfer_ownership_to_player(game, player1.id)

      assert updated_game.owner.id == player1.id
      assert updated_game.owner.username == player1.username

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [
        %{
          type: :ownership_transferred_to,
          payload: %{from_player_id: game.owner.id, to_player_id: player1.id}
        }
      ])
    end

    test "returns error when player is not in the game", %{game: game} do
      non_player = build_games_player("Non Player")

      assert {:error, :player_not_found} = Core.transfer_ownership_to_player(game, non_player.id)
    end

    test "returns error when player is already the owner", %{game: game, owner: owner} do
      assert {:error, :already_owner} =
               Core.transfer_ownership_to_player(game, owner.id)
    end

    test "works in any game state but archived", %{game: game, player2: player2} do
      # Test in playing state
      game_playing = %{game | status: :playing}
      {:ok, updated_game} = Core.transfer_ownership_to_player(game_playing, player2.id)
      assert updated_game.owner.id == player2.id

      # Test in finished state
      game_finished = %{game | status: :finished}
      {:ok, updated_game} = Core.transfer_ownership_to_player(game_finished, player2.id)
      assert updated_game.owner.id == player2.id

      # Test in archived state
      game_archived = %{game | status: :archived}
      {:error, :game_archived} = Core.transfer_ownership_to_player(game_archived, player2.id)
    end
  end

  describe "authorize_settings_update/2 and update_settings/3" do
    setup %{owner: owner} do
      game = Core.new(owner, "Test Game", 4)
      {:ok, game: game}
    end

    test "AC-04: authorize_settings_update/2 enforces owner and lobby state", %{
      game: game,
      owner: owner
    } do
      other = build_games_player("Other")

      assert :ok = Core.authorize_settings_update(game, owner.id)
      assert {:error, :unauthorized} = Core.authorize_settings_update(game, other.id)

      assert {:error, :unauthorized} =
               Core.authorize_settings_update(%{game | owner: nil}, owner.id)

      assert {:error, :game_not_in_lobby} =
               Core.authorize_settings_update(%{game | status: :playing}, owner.id)

      assert {:error, :game_not_in_lobby} =
               Core.authorize_settings_update(%{game | status: :archived}, owner.id)
    end

    test "AC-04: updates settings when called by owner in lobby with validated RoomSettings",
         %{game: game, owner: owner} do
      cat_1 = Ecto.UUID.generate()
      cat_2 = Ecto.UUID.generate()

      settings = %RoomSettings{
        name: "  New Game Name  ",
        max_players: 6,
        word_options: %WordOptions{language: "pt", category_ids: [cat_1, cat_2]}
      }

      assert {:ok, updated_game} = Core.update_settings(game, owner.id, settings)

      assert updated_game.name == "New Game Name"
      assert updated_game.max_players == 6
      assert updated_game.word_options.language == "pt"
      assert updated_game.word_options.category_ids == [cat_1, cat_2]
      assert updated_game.tick == game.tick + 1
      assert_last_events(updated_game, [%{type: :settings_updated}])
    end

    test "AC-04: returns {:error, :unauthorized} when called by a non-owner", %{game: game} do
      other = build_games_player("Other")
      settings = %RoomSettings{name: "Hijacked", max_players: 4, word_options: %WordOptions{}}

      assert {:error, :unauthorized} = Core.update_settings(game, other.id, settings)
    end

    test "AC-04: returns {:error, :invalid_name} for blank, whitespace-only, or over-60-char name",
         %{game: game, owner: owner} do
      base = %RoomSettings{name: "Sala", max_players: 4, word_options: %WordOptions{}}

      assert {:error, :invalid_name} = Core.update_settings(game, owner.id, %{base | name: "   "})

      assert {:error, :invalid_name} =
               Core.update_settings(game, owner.id, %{base | name: String.duplicate("a", 61)})
    end

    test "AC-04: returns {:error, :invalid_max_players} for max_players outside 2..6", %{
      game: game,
      owner: owner
    } do
      base = %RoomSettings{name: "Sala", max_players: 4, word_options: %WordOptions{}}

      assert {:error, :invalid_max_players} =
               Core.update_settings(game, owner.id, %{base | max_players: 1})

      assert {:error, :invalid_max_players} =
               Core.update_settings(game, owner.id, %{base | max_players: 10})
    end

    test "EDGE-01: returns {:error, :invalid_max_players} when max_players is below current occupancy",
         %{game: game, owner: owner} do
      p1 = build_games_player("P1")
      p2 = build_games_player("P2")
      p3 = build_games_player("P3")

      {:ok, game} = Core.join_game(game, owner)
      {:ok, game} = Core.join_game(game, p1)
      {:ok, game} = Core.join_game(game, p2)
      {:ok, game} = Core.join_game(game, p3)

      settings = %RoomSettings{name: "Sala", max_players: 3, word_options: %WordOptions{}}
      assert {:error, :invalid_max_players} = Core.update_settings(game, owner.id, settings)
    end

    test "EDGE-02: rejects nil word_options or unsupported language", %{
      game: game,
      owner: owner
    } do
      nil_wo = %RoomSettings{name: "Sala", max_players: 4, word_options: nil}
      assert {:error, :invalid_word_options} = Core.update_settings(game, owner.id, nil_wo)

      bad_lang = %RoomSettings{
        name: "Sala",
        max_players: 4,
        word_options: %WordOptions{language: "es", category_ids: []}
      }

      assert {:error, :invalid_word_options} = Core.update_settings(game, owner.id, bad_lang)
    end

    test "AC-04: returns {:error, :game_not_in_lobby} when not in lobby state", %{
      game: game,
      owner: owner
    } do
      settings = %RoomSettings{name: "New Name", max_players: 6, word_options: %WordOptions{}}

      assert {:error, :game_not_in_lobby} =
               Core.update_settings(%{game | status: :playing}, owner.id, settings)

      assert {:error, :game_not_in_lobby} =
               Core.update_settings(%{game | status: :archived}, owner.id, settings)
    end
  end

  describe "to_game_summary/1" do
    setup %{owner: owner} do
      # Create a new game
      game = Core.new(owner, "Test Game", 4)

      {:ok, game: game}
    end

    test "returns a GameSummary struct", %{game: game} do
      summary = Core.to_game_summary(game)

      assert %Forka.Games.GameSummary{} = summary
    end
  end

  describe "join_room/2" do
    setup %{owner: owner} do
      game = Core.new(owner, "Sala de Teste", 2)
      player1 = build_games_player("Player 1")
      player2 = build_games_player("Player 2")
      player3 = build_games_player("Player 3")
      {:ok, game: game, player1: player1, player2: player2, player3: player3}
    end

    test "REQ-05: returns {:ok, :joined, state} for new player in lobby with open seat", %{
      game: game,
      player1: player1
    } do
      assert {:ok, :joined, updated} = Core.join_room(game, player1)
      assert map_size(updated.game_players) == 1
      assert updated.tick == game.tick + 1
      assert_last_events(updated, [%{type: :player_joined, payload: %{player_id: player1.id}}])
    end

    test "REQ-05: returns {:ok, :already_joined, state} without duplicate event for existing lobby participant",
         %{
           game: game,
           player1: player1
         } do
      {:ok, :joined, joined_game} = Core.join_room(game, player1)
      joined_game = %{joined_game | events: []}

      assert {:ok, :already_joined, returned} = Core.join_room(joined_game, player1)
      assert returned.tick == joined_game.tick
      assert returned.events == []
      assert map_size(returned.game_players) == 1
    end

    test "REQ-04: returns {:error, :maximum_players} when lobby is full for a new player", %{
      game: game,
      player1: player1,
      player2: player2,
      player3: player3
    } do
      {:ok, :joined, g1} = Core.join_room(game, player1)
      {:ok, :joined, g2} = Core.join_room(g1, player2)

      assert {:error, :maximum_players} = Core.join_room(g2, player3)
    end

    test "REQ-05: returns {:ok, :returning_participant, state} for existing participant in playing or ended match",
         %{
           game: game,
           player1: player1,
           player2: player2
         } do
      {:ok, :joined, g1} = Core.join_room(game, player1)
      {:ok, :joined, g2} = Core.join_room(g1, player2)

      for status <- [:playing, :finished, :game_over] do
        in_match = %{g2 | status: status, events: []}
        assert {:ok, :returning_participant, returned} = Core.join_room(in_match, player1)
        assert returned.tick == in_match.tick
        assert returned.events == []
      end
    end

    test "REQ-04: returns {:error, :game_already_started} or {:error, :game_ended} for non-participant",
         %{
           game: game,
           player1: player1,
           player2: player2,
           player3: player3
         } do
      {:ok, :joined, g1} = Core.join_room(game, player1)
      {:ok, :joined, g2} = Core.join_room(g1, player2)

      assert {:error, :game_already_started} = Core.join_room(%{g2 | status: :playing}, player3)
      assert {:error, :game_ended} = Core.join_room(%{g2 | status: :finished}, player3)
      assert {:error, :game_ended} = Core.join_room(%{g2 | status: :game_over}, player3)
    end

    test "REQ-04: returns {:error, :game_archived} when game is archived", %{
      game: game,
      player1: player1
    } do
      assert {:error, :game_archived} = Core.join_room(%{game | status: :archived}, player1)
    end

    property "REQ-05: repeat join_room/2 leaves existing participant membership, events, and tick unchanged" do
      check all(
              max_players <- StreamData.integer(2..6),
              roster_size <- StreamData.integer(1..max_players),
              status <- StreamData.member_of([:lobby, :playing, :finished, :game_over]),
              pick_index <- StreamData.integer(0..(roster_size - 1))
            ) do
        owner = build_games_player("Owner")
        base = Core.new(owner, "Sala Propriedade", max_players)
        players = Enum.map(1..roster_size, &build_games_player("P#{&1}"))

        populated =
          Enum.reduce(players, base, fn player, acc ->
            {:ok, :joined, next} = Core.join_room(acc, player)
            next
          end)

        state = %{populated | status: status, events: []}
        existing = Enum.at(players, pick_index)
        expected_outcome = if status == :lobby, do: :already_joined, else: :returning_participant

        assert {:ok, ^expected_outcome, returned} = Core.join_room(state, existing)
        assert returned.game_players == state.game_players
        assert returned.tick == state.tick
        assert returned.events == []
      end
    end
  end
end
