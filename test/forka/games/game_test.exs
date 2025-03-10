defmodule Forka.Games.GameTest do
  use ExUnit.Case
  alias Forka.Games.{Game, Player, Word}

  describe "new/2" do
    test "creates a new game with valid parameters" do
      name = "Test Game"
      max_players = 4
      game = Game.new(name, max_players)

      assert %Game.GameState{} = game
      assert is_binary(game.id)
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
    setup do
      game = Game.new("Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game: game, player: player}
    end

    test "adds player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Game.add_player(game, player)

      assert map_size(updated_game.players) == 1

      assert Enum.any?(updated_game.players, fn {_idx, game_player} ->
               game_player.player.id == player.id &&
                 game_player.player.username == player.username &&
                 game_player.status == :alive &&
                 game_player.lives == 6 &&
                 game_player.connection_status == :disconnected &&
                 game_player.score == 0
             end)
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
  end

  describe "remove_player/2" do
    setup do
      game = Game.new("Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)
      {:ok, game: game_with_player, player: player}
    end

    test "removes player successfully when in lobby", %{game: game, player: player} do
      {:ok, updated_game} = Game.remove_player(game, player)
      assert map_size(updated_game.players) == 0
    end

    test "returns error when game already started", %{game: game, player: player} do
      game_started = %{game | status: :playing}
      assert {:error, :game_already_started} = Game.remove_player(game_started, player)
    end

    test "returns error when player not found", %{game: game} do
      unknown_player = Player.new("Unknown")
      assert {:error, :player_not_found} = Game.remove_player(game, unknown_player)
    end
  end

  describe "connect_player/2" do
    setup do
      game = Game.new("Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)
      {:ok, game: game_with_player, player: player}
    end

    test "connects player successfully", %{game: game, player: player} do
      {:ok, updated_game} = Game.connect_player(game, player)

      {_idx, game_player} = find_player_by_id(updated_game.players, player.id)
      assert game_player.connection_status == :connected
    end

    test "returns error when player not found", %{game: game} do
      unknown_player = Player.new("Unknown")
      assert {:error, :player_not_found} = Game.connect_player(game, unknown_player)
    end
  end

  describe "disconnect_player/2" do
    setup do
      game = Game.new("Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)
      {:ok, connected_game} = Game.connect_player(game_with_player, player)
      {:ok, game: connected_game, player: player}
    end

    test "disconnects player successfully", %{game: game, player: player} do
      {:ok, updated_game} = Game.disconnect_player(game, player)

      {_idx, game_player} = find_player_by_id(updated_game.players, player.id)
      assert game_player.connection_status == :disconnected
    end

    test "returns error when player not found", %{game: game} do
      unknown_player = Player.new("Unknown")
      assert {:error, :player_not_found} = Game.disconnect_player(game, unknown_player)
    end
  end

  describe "give_up_player/2" do
    setup do
      game = Game.new("Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)
      {:ok, game: game_with_player, player: player}
    end

    test "makes player give up successfully", %{game: game, player: player} do
      {:ok, updated_game} = Game.give_up_player(game, player)

      {_idx, game_player} = find_player_by_id(updated_game.players, player.id)
      assert game_player.status == :died
      assert game_player.lives == 0
    end

    test "returns error when player not found", %{game: game} do
      unknown_player = Player.new("Unknown")
      assert {:error, :player_not_found} = Game.give_up_player(game, unknown_player)
    end
  end

  describe "set_game_words/2" do
    setup do
      game = Game.new("Test Game", 4)

      words = [
        %Word{word: "cat", category: "Animals", hint: "Meows"},
        %Word{word: "dog", category: "Animals", hint: "Barks"}
      ]

      {:ok, game: game, words: words}
    end

    test "sets words successfully", %{game: game, words: words} do
      {:ok, updated_game} = Game.set_game_words(game, words)
      assert map_size(updated_game.words) == 2

      Enum.each(updated_game.words, fn {_idx, game_word} ->
        assert %Game.GameWord{} = game_word
        assert game_word.guesses == []
        assert game_word.finished_by_id == nil
      end)
    end

    test "removes duplicate words", %{game: game, words: words} do
      duplicate_words = words ++ [List.first(words)]
      {:ok, updated_game} = Game.set_game_words(game, duplicate_words)
      assert map_size(updated_game.words) == 2
    end
  end

  describe "init_game/1" do
    setup do
      game = Game.new("Test Game", 4)
      player1 = Player.new("Player 1")
      player2 = Player.new("Player 2")
      word = %Word{word: "cat", category: "Animals", hint: "Meows"}

      {:ok, game_with_player1} = Game.add_player(game, player1)
      {:ok, game_with_players} = Game.add_player(game_with_player1, player2)
      {:ok, game_with_words} = Game.set_game_words(game_with_players, [word])

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

    test "returns error when not enough players" do
      game = Game.new("Test Game", 4)
      player = Player.new("Player 1")
      {:ok, game_with_player} = Game.add_player(game, player)

      assert {:error, :game_not_ready} = Game.init_game(game_with_player)
    end
  end

  # Helper function to find player by ID
  defp find_player_by_id(players, player_id) do
    Enum.find(players, fn {_idx, game_player} -> game_player.player.id == player_id end)
  end
end
