defmodule Forka.Games.Game.GameLogicTest do
  use ExUnit.Case, async: true
  alias Forka.Games.{Game, Player, Word}
  alias Forka.Games.Game.{GameLogic, GameState, GamePlayer}

  import Forka.Games.Game.Helpers

  setup do
    # Create owner
    owner = Player.new("Owner")

    # Create players
    player1 = Player.new("Player 1")
    player2 = Player.new("Player 2")

    # Create words
    word1 = Word.new("cat", "animals", "Meows")
    word2 = Word.new("dog", "animals", "Barks")

    # Create a game
    game = Game.new(owner, "Test Game", 4)
    {:ok, game_with_player1} = Game.join_game(game, player1)
    {:ok, game_with_players} = Game.join_game(game_with_player1, player2)
    game_with_words = Game.set_words(game_with_players, [word1, word2])
    {:ok, initialized_game} = Game.start_game(game_with_words)

    {:ok,
     game_state: initialized_game, player1: player1, player2: player2, word1: word1, word2: word2}
  end

  describe "get_current_player/1" do
    test "returns the current player", %{game_state: game, player1: player1} do
      assert %Player{id: player_id} = Game.get_current_player(game)
      assert player_id == player1.id
    end

    test "returns the next alive player if the current player is dead", %{
      game_state: game,
      player1: player1,
      player2: player2
    } do
      # Mark player1 as dead
      game_with_dead_player1 = %{
        game
        | players: %{
            0 => %GamePlayer{player: player1, status: :dead},
            1 => %GamePlayer{player: player2, status: :alive}
          },
          current_game_player_index: 0
      }

      # Get the current player, which should now be player2
      assert %Player{id: player_id} = Game.get_current_player(game_with_dead_player1)
      assert player_id == player2.id
    end

    test "returns error when no current player", %{game_state: game} do
      game_without_players = %{game | players: %{}, current_game_player_index: nil}
      assert Game.get_current_player(game_without_players) == nil
    end
  end

  describe "give_up_game/2" do
    test "makes player give up successfully", %{game_state: game, player1: player} do
      {:ok, updated_game} = GameLogic.give_up_game(game, player.id)

      assert updated_game.last_event == {:player_gave_up, player}

      {_idx, game_player} = find_game_player_by_id(updated_game, player.id)
      assert game_player.status == :dead
      assert game_player.lives == 0
    end

    test "moves to next alive player when player gives up", %{
      game_state: initialized_game,
      player1: player1,
      player2: player2
    } do
      # Player 1 gives up
      {:ok, updated_game} = GameLogic.give_up_game(initialized_game, player1.id)

      # Check that the current player is now Player 2
      assert %Player{id: current_player_id} = GameLogic.get_current_player(updated_game)
      assert current_player_id == player2.id
    end

    test "game is over when all players give up", %{
      game_state: game_state,
      player1: player1,
      player2: player2
    } do
      # Player 1 gives up
      {:ok, game_after_p1} = GameLogic.give_up_game(game_state, player1.id)

      # Game should still be playing with one player left
      assert game_after_p1.status == :playing

      # Player 2 gives up
      {:ok, game_after_p2} = GameLogic.give_up_game(game_after_p1, player2.id)

      # Game should now be over since all players gave up
      assert game_after_p2.status == :game_over

      # Both players should be marked as dead
      {_, player1_state} = find_game_player_by_id(game_after_p2, player1.id)
      {_, player2_state} = find_game_player_by_id(game_after_p2, player2.id)
      assert player1_state.status == :dead
      assert player2_state.status == :dead

      # Current player and word indices should be nil in game over state
      assert game_after_p2.current_game_player_index == nil
      assert game_after_p2.current_game_word_index == nil
    end

    test "returns error when player not found", %{game_state: game} do
      unknown_player = Player.new("Unknown")
      assert {:error, :player_not_found} = GameLogic.give_up_game(game, unknown_player.id)
    end

    test "returns error when game is archived", %{game_state: game, player1: player1} do
      # Set game status to archived
      archived_game = %{game | status: :archived}

      # Try to give up in an archived game
      assert {:error, :game_archived} = GameLogic.give_up_game(archived_game, player1.id)
    end
  end

  describe "guess/3" do
    test "returns error when not player's turn", %{game_state: game_state, player2: player2} do
      # Player 2 tries to guess but it's player 1's turn
      assert {:error, :not_player_turn} = GameLogic.guess(game_state, player2.id, "a")
    end

    test "processes correct guess successfully", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'c' in 'cat'
      assert {:ok, updated_game} = GameLogic.guess(game_state, player1.id, "c")

      # Check that the guess was recorded
      current_word = get_current_word(updated_game)

      assert Enum.any?(current_word.guesses, fn guess ->
               guess.letter == "c" && guess.correct? == true
             end)

      # Player should get points for correct guess
      player = get_current_player(updated_game)
      assert player.score > 0

      # Check if correct guess was processed correctly
      [guess] = current_word.guesses
      assert updated_game.last_event == {:player_guessed, guess}
    end

    test "processes incorrect guess successfully", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'z' which is not in 'cat'
      assert {:ok, updated_game} = GameLogic.guess(game_state, player1.id, "z")

      # Check that the guess was recorded
      current_word = get_current_word(updated_game)

      assert Enum.any?(current_word.guesses, fn guess ->
               guess.letter == "z" && guess.correct? == false
             end)

      # Player should lose a life
      player = get_player_by_id(updated_game, player1.id)
      assert player.lives == 5

      # Turn should move to next player
      current_player = get_current_player(updated_game)
      refute current_player.player.id == player1.id

      # Check if incorrect guess was processed correctly
      [guess] = current_word.guesses
      assert updated_game.last_event == {:player_guessed, guess}
    end

    test "returns error for already guessed letter", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'c'
      {:ok, updated_game} = GameLogic.guess(game_state, player1.id, "c")

      # Player 1 tries to guess 'c' again
      assert {:error, :letter_already_guessed} = GameLogic.guess(updated_game, player1.id, "c")
    end

    test "returns error when game is not in playing status", %{
      game_state: game_state,
      player1: player1
    } do
      # Set game status to finished
      game_state = %{game_state | status: :finished}
      assert {:error, :game_not_playing} = GameLogic.guess(game_state, player1.id, "a")

      # Set game status to game_over
      game_state = %{game_state | status: :game_over}
      assert {:error, :game_not_playing} = GameLogic.guess(game_state, player1.id, "a")
    end

    test "returns error when game is archived", %{game_state: game_state, player1: player1} do
      # Set game status to archived
      archived_game = %{game_state | status: :archived}

      # Try to make a guess in an archived game
      assert {:error, :game_archived} = GameLogic.guess(archived_game, player1.id, "a")
    end
  end

  describe "game completion scenarios" do
    test "player completes a word and moves to next word", %{
      game_state: game_state,
      player1: player1
    } do
      # Player 1 guesses all letters in 'cat'
      {:ok, game_after_c} = GameLogic.guess(game_state, player1.id, "c")
      {:ok, game_after_a} = GameLogic.guess(game_after_c, player1.id, "a")
      {:ok, game_after_t} = GameLogic.guess(game_after_a, player1.id, "t")

      # Check that we moved to the next word
      assert game_after_t.current_game_word_index == 1

      # Player should get bonus points for completing the word
      player = get_player_by_id(game_after_t, player1.id)
      # Base points plus completion bonus
      assert player.score > 30

      # Player's lives should be reset
      assert player.lives == 6
    end

    test "player wins the game by completing all words", %{
      game_state: game_state,
      player1: player1
    } do
      # Complete first word 'cat'
      {:ok, game_after_c} = GameLogic.guess(game_state, player1.id, "c")
      {:ok, game_after_a} = GameLogic.guess(game_after_c, player1.id, "a")
      {:ok, game_after_t} = GameLogic.guess(game_after_a, player1.id, "t")

      # Complete second word 'dog'
      {:ok, game_after_d} = GameLogic.guess(game_after_t, player1.id, "d")
      {:ok, game_after_o} = GameLogic.guess(game_after_d, player1.id, "o")
      {:ok, game_after_g} = GameLogic.guess(game_after_o, player1.id, "g")

      # Game should be finished
      assert game_after_g.status == :finished
    end

    test "one player wins while another dies", %{
      game_state: game_state,
      player1: player1,
      player2: player2
    } do
      # Player 1 makes incorrect guesses and loses turn
      {:ok, game_after_z} = GameLogic.guess(game_state, player1.id, "z")

      # Now it's player 2's turn
      # Player 2 makes 6 incorrect guesses and dies
      {:ok, game_after_x} = GameLogic.guess(game_after_z, player2.id, "x")
      {:ok, game_after_v} = GameLogic.guess(game_after_x, player1.id, "v")
      {:ok, game_after_b} = GameLogic.guess(game_after_v, player2.id, "b")
      {:ok, game_after_n} = GameLogic.guess(game_after_b, player1.id, "n")
      {:ok, game_after_m} = GameLogic.guess(game_after_n, player2.id, "m")
      {:ok, game_after_q} = GameLogic.guess(game_after_m, player1.id, "q")
      {:ok, game_after_w} = GameLogic.guess(game_after_q, player2.id, "w")
      {:ok, game_after_e} = GameLogic.guess(game_after_w, player1.id, "e")
      {:ok, game_after_r} = GameLogic.guess(game_after_e, player2.id, "r")
      # Player 1 complete to earn more lives, and win player 2
      {:ok, game_after_c} = GameLogic.guess(game_after_r, player1.id, "c")
      {:ok, game_after_a} = GameLogic.guess(game_after_c, player1.id, "a")
      {:ok, game_after_t} = GameLogic.guess(game_after_a, player1.id, "t")
      # Player 2 loose in another word
      {:ok, game_after_x} = GameLogic.guess(game_after_t, player1.id, "x")
      {:ok, game_after_y} = GameLogic.guess(game_after_x, player2.id, "y")
      {:ok, game_after_z} = GameLogic.guess(game_after_y, player1.id, "z")
      {:ok, game_after_a} = GameLogic.guess(game_after_z, player2.id, "a")

      # Player 2 should be dead
      player2_state = get_player_by_id(game_after_a, player2.id)
      assert player2_state.status == :dead

      # Player 1 completes the words and wins
      {:ok, game_after_c} = GameLogic.guess(game_after_m, player1.id, "c")
      {:ok, game_after_a} = GameLogic.guess(game_after_c, player1.id, "a")
      {:ok, game_after_t} = GameLogic.guess(game_after_a, player1.id, "t")

      # Complete second word 'dog'
      {:ok, game_after_d} = GameLogic.guess(game_after_t, player1.id, "d")
      {:ok, game_after_o} = GameLogic.guess(game_after_d, player1.id, "o")
      {:ok, game_after_g} = GameLogic.guess(game_after_o, player1.id, "g")

      # Game should be finished with player 1 as winner
      assert game_after_g.status == :finished
    end

    test "game over when all players die", %{
      game_state: game_state,
      player1: player1,
      player2: player2
    } do
      # Make both players die by making 6 incorrect guesses each

      # Player 1 makes incorrect guesses
      {:ok, game_after_z1} = GameLogic.guess(game_state, player1.id, "z")

      # Player 2 makes incorrect guesses
      {:ok, game_after_x1} = GameLogic.guess(game_after_z1, player2.id, "x")

      # Continue alternating incorrect guesses
      {:ok, game_after_v1} = GameLogic.guess(game_after_x1, player1.id, "v")
      {:ok, game_after_b1} = GameLogic.guess(game_after_v1, player2.id, "b")
      {:ok, game_after_n1} = GameLogic.guess(game_after_b1, player1.id, "n")
      {:ok, game_after_m1} = GameLogic.guess(game_after_n1, player2.id, "m")
      {:ok, game_after_q1} = GameLogic.guess(game_after_m1, player1.id, "q")
      {:ok, game_after_w1} = GameLogic.guess(game_after_q1, player2.id, "w")
      {:ok, game_after_e1} = GameLogic.guess(game_after_w1, player1.id, "e")
      {:ok, game_after_r1} = GameLogic.guess(game_after_e1, player2.id, "r")
      {:ok, game_after_y1} = GameLogic.guess(game_after_r1, player1.id, "y")
      {:ok, game_after_u1} = GameLogic.guess(game_after_y1, player2.id, "u")
      {:ok, game_after_i1} = GameLogic.guess(game_after_u1, player1.id, "i")
      {:ok, game_after_o1} = GameLogic.guess(game_after_i1, player2.id, "o")

      # Game should be over
      assert game_after_o1.status == :game_over

      # Both players should be dead
      player1_state = get_player_by_id(game_after_o1, player1.id)
      player2_state = get_player_by_id(game_after_o1, player2.id)
      assert player1_state.status == :dead
      assert player2_state.status == :dead
    end
  end

  describe "edge cases" do
    test "player automatically skipped when dead", %{
      game_state: game_state,
      player1: player1,
      player2: player2
    } do
      player_index = game_state.current_game_player_index
      player = Map.get(game_state.players, player_index)
      dead_player = %{player | status: :dead, lives: 0}

      game_with_dead_player = %{
        game_state
        | players: Map.put(game_state.players, player_index, dead_player)
      }

      # Try to guess with player 1 (who is now dead)
      {:error, :not_player_turn} = GameLogic.guess(game_with_dead_player, player1.id, "a")

      # Try to guess with player 2
      assert {:ok, _game_} = GameLogic.guess(game_with_dead_player, player2.id, "a")
    end
  end

  # Helper functions
  defp get_current_word(%GameState{words: words, current_game_word_index: index}) do
    Map.get(words, index)
  end

  defp get_current_player(%GameState{players: players, current_game_player_index: index}) do
    Map.get(players, index)
  end

  defp get_player_by_id(%GameState{players: players}, player_id) do
    {_idx, player} =
      Enum.find(players, fn {_idx, game_player} ->
        game_player.player.id == player_id
      end)

    player
  end
end
