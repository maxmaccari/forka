defmodule Forka.Games.GameTest do
  use ExUnit.Case, async: true
  alias Forka.Games.{Game, Player, Word}

  setup do
    owner = Player.new("Owner")

    %{owner: owner}
  end

  describe "new/2" do
    test "creates a new game with valid parameters", %{owner: owner} do
      name = "Test Game"
      max_players = 4
      game = Game.new(owner, name, max_players)

      assert game.owner == owner
      assert game.name == name
      assert game.max_players == max_players
      assert game.status == :lobby
      assert game.words == %{}
      assert game.players == %{}
      assert game.current_game_word_index == nil
      assert game.current_game_player_index == nil
    end
  end

  describe "add_player/2" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game: game, player: player}
    end

    test "adds player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Game.add_player(game, player)

      assert map_size(updated_game.players) == 1

      assert %{0 => game_player} = updated_game.players

      assert game_player.player.id == player.id
      assert game_player.player.username == player.username
      assert game_player.status == :alive
      assert game_player.lives == 6
      assert game_player.score == 0
    end

    test "adds players in sequential order", %{game: game} do
      player1 = Player.new("Player 1")
      player2 = Player.new("Player 2")
      player3 = Player.new("Player 3")

      {:ok, game_with_player1} = Game.add_player(game, player1)
      {:ok, game_with_player2} = Game.add_player(game_with_player1, player2)
      {:ok, game_with_player3} = Game.add_player(game_with_player2, player3)

      assert map_size(game_with_player3.players) == 3
      assert %{0 => %{player: %{username: "Player 1"}}} = game_with_player3.players
      assert %{1 => %{player: %{username: "Player 2"}}} = game_with_player3.players
      assert %{2 => %{player: %{username: "Player 3"}}} = game_with_player3.players
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Game.add_player(game_started, player)
    end

    test "returns error when max players reached", %{game: game, player: player} do
      game = %{game | max_players: 1}
      {:ok, game_with_player} = Game.add_player(game, player)

      player2 = Player.new("Player 2")
      assert {:error, :maximum_players} = Game.add_player(game_with_player, player2)
    end

    test "returns error when game is archived", %{game: game, player: player} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Game.add_player(game_archived, player)
    end
  end

  describe "remove_player/2" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)
      {:ok, game: game_with_player, player: player}
    end

    test "removes player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Game.remove_player(game, player.id)
      assert map_size(updated_game.players) == 0
    end

    test "reindexes players after removal", %{game: game_with_player1} do
      player2 = Player.new("Player 2")
      player3 = Player.new("Player 3")

      {:ok, game_with_player2} = Game.add_player(game_with_player1, player2)
      {:ok, game_with_player3} = Game.add_player(game_with_player2, player3)

      {:ok, updated_game} = Game.remove_player(game_with_player3, player2.id)

      # Check that player3 is now at index 1 (second position)
      assert map_size(updated_game.players) == 2
      assert %{0 => %{player: %{username: "Player 1"}}} = updated_game.players
      assert %{1 => %{player: %{username: "Player 3"}}} = updated_game.players
    end

    test "returns unchanged game when removing player that doesn't exist", %{game: game} do
      unknown_player = Player.new("Unknown")
      assert {:ok, ^game} = Game.remove_player(game, unknown_player.id)
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Game.remove_player(game_started, player.id)
    end

    test "returns error when game is archived", %{game: game, player: player} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Game.remove_player(game_archived, player.id)
    end
  end

  describe "set_words/2" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)

      words = [
        Word.new("cat", "animals", "Meows"),
        Word.new("dog", "animals", "Barks")
      ]

      {:ok, game: game, words: words}
    end

    test "sets words successfully", %{game: game, words: words} do
      assert updated_game = Game.set_words(game, words)
      assert map_size(updated_game.words) == 2

      Enum.each(updated_game.words, fn {_idx, game_word} ->
        assert %Game.GameWord{} = game_word
        assert game_word.guesses == []
        assert game_word.finished_by_id == nil
      end)
    end

    test "removes duplicate words", %{game: game, words: words} do
      duplicate_words = words ++ [List.first(words)]
      updated_game = Game.set_words(game, duplicate_words)
      assert map_size(updated_game.words) == 2
    end

    test "does not set words when game is not in lobby state", %{game: game, words: words} do
      game_playing = %{game | status: :playing}
      assert ^game_playing = Game.set_words(game_playing, words)

      game_archived = %{game | status: :archived}
      assert ^game_archived = Game.set_words(game_archived, words)
    end
  end

  describe "shuffle_players/1" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 10)

      # Add multiple players to ensure we have enough for shuffling
      players = for i <- 1..10, do: Player.new("Player #{i}")

      # Add all players to the game
      game_with_players =
        Enum.reduce(players, game, fn player, acc_game ->
          {:ok, updated_game} = Game.add_player(acc_game, player)
          updated_game
        end)

      {:ok, game: game_with_players, players: players}
    end

    test "shuffles players only in lobby state", %{game: game} do
      # Test in lobby state
      shuffled_game = Game.shuffle_players(game)
      assert shuffled_game.status == :lobby

      # The player IDs should be the same, but potentially in different order
      original_player_ids =
        game.players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      shuffled_player_ids =
        shuffled_game.players |> Map.values() |> Enum.map(& &1.player.id) |> MapSet.new()

      assert original_player_ids == shuffled_player_ids

      # Verify player indices are sequential and start from 0
      player_indices = shuffled_game.players |> Map.keys() |> Enum.sort()
      assert player_indices == Enum.to_list(0..(map_size(shuffled_game.players) - 1))

      # Test in playing state - should not shuffle
      game_playing = %{game | status: :playing}
      assert ^game_playing = Game.shuffle_players(game_playing)

      # Test in archived state - should not shuffle
      game_archived = %{game | status: :archived}
      assert ^game_archived = Game.shuffle_players(game_archived)
    end

    test "maintains consistent state after shuffle", %{game: game} do
      shuffled_game = Game.shuffle_players(game)

      # Player count should remain the same
      assert map_size(game.players) == map_size(shuffled_game.players)

      # Each player should maintain their properties
      Enum.each(shuffled_game.players, fn {_idx, game_player} ->
        assert game_player.status == :alive
        assert game_player.lives == 6
        assert game_player.score == 0
      end)
    end
  end

  describe "init_game/1" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player1 = Player.new("Player 1")
      player2 = Player.new("Player 2")
      word = Word.new("cat", "Animals", "Meows")

      {:ok, game_with_player1} = Game.add_player(game, player1)
      {:ok, game_with_players} = Game.add_player(game_with_player1, player2)
      game_with_words = Game.set_words(game_with_players, [word])

      {:ok, game: game_with_words}
    end

    test "initializes game successfully when ready", %{game: game} do
      {:ok, initialized_game} = Game.init_game(game)

      assert initialized_game.status == :playing
      assert initialized_game.current_game_word_index == 0
      assert initialized_game.current_game_player_index == 0
      assert map_size(initialized_game.players) == 2
      assert map_size(initialized_game.words) == 1
    end

    test "returns error when game not in lobby", %{game: game} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_initialized} = Game.init_game(game_started)
    end

    test "returns error when not enough players", %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)

      assert {:error, :game_not_ready} = Game.init_game(game_with_player)
    end

    test "returns error when game is archived", %{game: game} do
      game_archived = %{game | status: :archived}
      assert {:error, :game_archived} = Game.init_game(game_archived)
    end
  end

  describe "restart_game/1" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player1 = Player.new("Player 1")
      player2 = Player.new("Player 2")
      word = Word.new("cat", "Animals", "Meows")

      {:ok, game_with_player1} = Game.add_player(game, player1)
      {:ok, game_with_players} = Game.add_player(game_with_player1, player2)
      game_with_words = Game.set_words(game_with_players, [word])

      {:ok, initialized_game} = Game.init_game(game_with_words)

      # Create a finished game with some player state changes
      finished_game = %{initialized_game | status: :finished}

      # Simulate a player with reduced lives and dead status
      updated_players =
        Map.update!(
          finished_game.players,
          0,
          fn player -> %{player | lives: 0, status: :dead} end
        )

      finished_game_with_player_changes = %{finished_game | players: updated_players}

      {:ok,
       game_lobby: game_with_words,
       game_playing: initialized_game,
       game_finished: finished_game_with_player_changes}
    end

    test "restarts game successfully when in finished status", %{game_finished: game} do
      assert {:ok, restarted_game} = Game.restart_game(game)

      # Check that game is back in lobby state
      assert restarted_game.status == :lobby

      # Check that player lives and status are reset
      Enum.each(restarted_game.players, fn {_idx, player} ->
        assert player.lives == 6
        assert player.status == :alive
      end)

      # Check that game state is properly reset
      assert restarted_game.current_game_player_index == nil
      assert restarted_game.current_game_word_index == nil
      assert restarted_game.words == %{}
    end

    test "restarts game successfully when in lobby status", %{game_lobby: game} do
      assert {:ok, restarted_game} = Game.restart_game(game)
      assert restarted_game.status == :lobby
    end

    test "returns error when game is in playing status", %{game_playing: game} do
      assert {:error, :game_in_progress} = Game.restart_game(game)
    end

    test "returns error when game is archived", %{game_finished: game} do
      # First archive the game
      {:ok, archived_game} = Game.archive_game(game)
      assert archived_game.status == :archived

      # Then try to restart it
      assert {:error, :game_archived} = Game.restart_game(archived_game)
    end
  end

  describe "archive_game/1" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player1 = Player.new("Player 1")
      player2 = Player.new("Player 2")
      word = Word.new("cat", "Animals", "Meows")

      {:ok, game_with_player1} = Game.add_player(game, player1)
      {:ok, game_with_players} = Game.add_player(game_with_player1, player2)
      game_with_words = Game.set_words(game_with_players, [word])

      {:ok, initialized_game} = Game.init_game(game_with_words)

      # Create a finished game
      finished_game = %{initialized_game | status: :finished}

      {:ok,
       game_lobby: game_with_words, game_playing: initialized_game, game_finished: finished_game}
    end

    test "archives game successfully when in lobby status", %{game_lobby: game} do
      assert {:ok, archived_game} = Game.archive_game(game)
      assert archived_game.status == :archived
    end

    test "archives game successfully when in finished status", %{game_finished: game} do
      assert {:ok, archived_game} = Game.archive_game(game)
      assert archived_game.status == :archived
    end

    test "returns error when game is in playing status", %{game_playing: game} do
      assert {:error, :game_in_progress} = Game.archive_game(game)
    end

    test "cannot modify an archived game", %{game_lobby: game} do
      # First archive the game
      {:ok, archived_game} = Game.archive_game(game)
      assert archived_game.status == :archived

      # Verify that archived games cannot be modified
      player = Player.new("New Player")
      word = Word.new("dog", "Animals", "Barks")

      # Test various operations on archived game
      assert {:error, :game_archived} = Game.add_player(archived_game, player)
      assert {:error, :game_archived} = Game.remove_player(archived_game, "any_player_id")
      assert archived_game == Game.set_words(archived_game, [word])
      assert archived_game == Game.shuffle_players(archived_game)
      assert {:error, :game_archived} = Game.init_game(archived_game)
      assert {:error, :game_archived} = Game.guess(archived_game, "any_player_id", "a")
      assert {:error, :game_archived} = Game.give_up_player(archived_game, "any_player_id")
    end
  end

  describe "transfer_ownership_to_player/2" do
    setup %{owner: owner} do
      game = Game.new(owner, "Test Game", 4)
      player1 = Player.new("Player 1")
      player2 = Player.new("Player 2")

      {:ok, game_with_player1} = Game.add_player(game, player1)
      {:ok, game_with_players} = Game.add_player(game_with_player1, player2)

      {:ok, game: game_with_players, player1: player1, player2: player2, owner: owner}
    end

    test "transfers ownership successfully", %{game: game, player1: player1} do
      {:ok, updated_game} = Game.transfer_ownership_to_player(game, player1.id)

      assert updated_game.owner.id == player1.id
      assert updated_game.owner.username == player1.username
    end

    test "returns error when player is not in the game", %{game: game} do
      non_player = Player.new("Non Player")

      assert {:error, :player_not_found} = Game.transfer_ownership_to_player(game, non_player.id)
    end

    test "returns error when player is already the owner", %{game: game, owner: owner} do
      assert {:error, :already_owner} =
               Game.transfer_ownership_to_player(game, owner.id)
    end

    test "works in any game state but archived", %{game: game, player2: player2} do
      # Test in playing state
      game_playing = %{game | status: :playing}
      {:ok, updated_game} = Game.transfer_ownership_to_player(game_playing, player2.id)
      assert updated_game.owner.id == player2.id

      # Test in finished state
      game_finished = %{game | status: :finished}
      {:ok, updated_game} = Game.transfer_ownership_to_player(game_finished, player2.id)
      assert updated_game.owner.id == player2.id

      # Test in archived state
      game_archived = %{game | status: :archived}
      {:error, :game_archived} = Game.transfer_ownership_to_player(game_archived, player2.id)
    end
  end

  describe "to_game_summary/1" do
    setup %{owner: owner} do
      # Create a new game
      game = Game.new(owner, "Test Game", 4)

      {:ok, game: game}
    end

    test "returns a GameSummary struct", %{game: game} do
      summary = Game.to_game_summary(game)

      assert %Forka.Games.GameSummary{} = summary
    end
  end
end
