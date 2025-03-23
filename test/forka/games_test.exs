defmodule Forka.GamesTest do
  use Forka.DataCase

  alias Forka.Games

  import Forka.TestHelpers

  describe "list_games/1" do
    test "returns paginated games with count" do
      # Create test data
      owner = insert(:player)

      # Create games with different statuses
      insert(:game, owner: owner, status: :lobby, name: "Lobby Game 1")
      insert(:game, owner: owner, status: :lobby, name: "Lobby Game 2")
      insert(:game, owner: owner, status: :playing, name: "Playing Game 1")
      insert(:game, owner: owner, status: :playing, name: "Playing Game 2")
      insert(:game, owner: owner, status: :playing, name: "Playing Game 3")
      insert(:game, owner: owner, status: :archived, name: "Archived Game 1")

      # Test default pagination (first page)
      result = Games.list_games()
      assert %{games: games, games_count: count} = result
      assert length(games) == 6
      assert count == 6

      # Test with per_page option
      result = Games.list_games(per_page: 2)
      assert %{games: games, games_count: count} = result
      assert length(games) == 2
      assert count == 6

      # Test with page option
      result = Games.list_games(page: 2, per_page: 2)
      assert %{games: games, games_count: count} = result
      assert length(games) == 2
      assert count == 6

      # Test with game_status filter
      result = Games.list_games(game_status: :playing)
      assert %{games: games, games_count: count} = result
      assert length(games) == 3
      assert count == 3
      assert Enum.all?(games, fn game -> game.status == :playing end)

      # Test with combined pagination and status filter
      result = Games.list_games(page: 1, per_page: 1, game_status: :lobby)
      assert %{games: games, games_count: count} = result
      assert length(games) == 1
      assert count == 2
      assert hd(games).status == :lobby

      # Test with empty result
      result = Games.list_games(game_status: :finished)
      assert %{games: [], games_count: 0} = result
    end

    test "returns empty result when no games exist" do
      result = Games.list_games()
      assert %{games: [], games_count: 0} = result
    end
  end

  describe "create_game/2" do
    test "creates a game with valid parameters" do
      owner = insert(:player)
      params = %{name: "Test Game", max_players: 4}

      assert {:ok, game} = Games.create_game(owner.id, params)
      assert game.name == "Test Game"
      assert game.max_players == 4
      assert game.status == :lobby
      assert game.owner_id == owner.id
    end

    test "returns error with invalid parameters" do
      owner = insert(:player)
      params = %{name: nil, max_players: -1}

      assert {:error, changeset} = Games.create_game(owner.id, params)
      assert "can't be blank" in errors_on(changeset).name
      assert errors_on(changeset).max_players
    end
  end

  describe "update_settings/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Test Game", max_players: 4})
      %{game: game}
    end

    test "updates game settings in lobby state", %{game: game} do
      settings = %{name: "New Name", max_players: 6}
      assert :ok = Games.update_settings(game.id, settings)
      # Get the updated game to verify changes
      updated_game = Games.get_game_summary(game.id)
      assert updated_game.name == "New Name"
      assert updated_game.max_players == 6
    end

    test "returns error when game not in lobby", %{game: game} do
      # Add players and a word to start the game
      player1 = insert(:player)
      player2 = insert(:player)
      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      # Insert a word for the game
      insert(:word, %{text: "hangman"})

      # Start the game
      :ok = Games.start_game(game.id)

      settings = %{name: "New Name"}
      assert {:error, :game_not_in_lobby} = Games.update_settings(game.id, settings)
    end
  end

  describe "join_game/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, %{name: "Test Game", max_players: 4})
      %{game: game}
    end

    test "adds player to game successfully", %{game: game} do
      player = insert(:player)
      assert :ok = Games.join_game(game.id, player.id)

      # Verify player was added
      game_state = Games.get_game_summary(game.id)
      assert Enum.any?(game_state.players, fn {_, p} -> p.player.id == player.id end)
    end

    test "returns error when game is full", %{game: game} do
      # Fill game to max capacity
      for _ <- 1..game.max_players do
        player = insert(:player)
        Games.join_game(game.id, player.id)
      end

      extra_player = insert(:player)
      assert {:error, :maximum_players} = Games.join_game(game.id, extra_player.id)
    end
  end

  describe "leave_game/2" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      player = insert(:player)
      :ok = Games.join_game(game.id, player.id)
      %{game: game, player: player}
    end

    test "removes player from game", %{game: game, player: player} do
      assert :ok = Games.leave_game(game.id, player.id)

      game_state = Games.get_game_summary(game.id)
      refute Enum.any?(game_state.players, fn {_, p} -> p.player.id == player.id end)
    end
  end

  describe "start_game/1" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      insert(:word)

      %{game: game, players: [player1, player2]}
    end

    test "starts game successfully", %{game: game} do
      assert :ok = Games.start_game(game.id)

      game_summary = Games.get_game_summary(game.id)
      assert game_summary.game_status == :playing
      assert game_summary.current_player_id != nil
    end

    test "returns error with insufficient players", %{game: game, players: players} do
      # Remove all players except owner
      Enum.each(players, fn player ->
        Games.leave_game(game.id, player.id)
      end)

      assert {:error, :game_not_ready} = Games.start_game(game.id)
    end
  end

  describe "guess/3" do
    setup do
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      insert(:word, text: "banana")

      :ok = Games.start_game(game.id)
      %{game: game, players: [player1, player2]}
    end

    test "processes valid guess", %{game: game} do
      game_summary = Games.get_game_summary(game.id)
      current_player_id = game_summary.current_player_id

      assert :ok = Games.guess(game.id, current_player_id, "a")

      updated_state = Games.get_game_summary(game.id)
      assert "a" in Enum.map(updated_state.guesses, & &1.letter)
    end

    test "returns error for invalid player turn", %{game: game, players: players} do
      game_summary = Games.get_game_summary(game.id)

      non_current_player =
        Enum.find(players, fn player ->
          player.id != game_summary.current_player_id
        end)

      assert {:error, :not_player_turn} = Games.guess(game.id, non_current_player.id, "a")
    end
  end

  describe "game completion scenarios" do
    setup do
      word = insert(:word)

      owner = insert(:player)

      {:ok, game} = Games.create_game(owner.id, params_for(:game))

      player1 = insert(:player)
      player2 = insert(:player)

      :ok = Games.join_game(game.id, player1.id)
      :ok = Games.join_game(game.id, player2.id)

      :ok = Games.start_game(game.id)

      %{game: game, player1: player1, player2: player2, word: word}
    end

    test "game over when all players give up", %{game: game, player1: player1, player2: player2} do
      :ok = Games.give_up_game(game.id, player1.id)
      :ok = Games.give_up_game(game.id, player2.id)

      game_summary = Games.get_game_summary(game.id)
      assert game_summary.game_status == :game_over
      assert game_summary.current_player_id == nil
    end

    test "game finishes when all words completed", %{game: game, word: word} do
      # Extract all unique letters from the word
      unique_letters =
        word.text
        |> String.downcase()
        |> String.graphemes()
        |> Enum.uniq()

      # Get the current game state
      game_summary = Games.get_game_summary(game.id)

      # Guess each letter in the word to complete it
      for letter <- unique_letters do
        assert :ok = Games.guess(game.id, game_summary.current_player_id, letter)
      end

      # Verify the game is finished after all letters are guessed
      finished_game_summary = Games.get_game_summary(game.id)
      assert finished_game_summary.game_status == :finished
    end
  end

  describe "game subscriptions" do
    setup do
      insert(:word)
      owner = insert(:player)
      {:ok, game} = Games.create_game(owner.id, params_for(:game))
      :ok = Games.subscribe(game.id)
      %{game: game}
    end

    test "subscribers receive updates on game changes", %{game: game} do
      player = insert(:player)
      :ok = Games.join_game(game.id, player.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.players[0].player.id == player.id
    end

    test "subscribers receive game state changes", %{game: game} do
      :ok = Games.join_game(game.id, insert(:player).id)
      :ok = Games.join_game(game.id, insert(:player).id)

      flush_messages()

      :ok = Games.start_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing
    end
  end
end
