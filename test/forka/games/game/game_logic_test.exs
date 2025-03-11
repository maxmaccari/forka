defmodule Forka.Games.Game.GameLogicTest do
  use ExUnit.Case
  alias Forka.Games.{Game, Player, Word}
  alias Forka.Games.Game.{GameLogic, GameState, GameWord, GamePlayer}

  import Forka.Games.Game.Helpers

  setup do
    # Create players
    player1 = Player.new("Player 1")
    player2 = Player.new("Player 2")

    # Create words
    word1 = %Word{word: "cat", category: "Animals", hint: "Meows"}
    word2 = %Word{word: "dog", category: "Animals", hint: "Barks"}

    # Create a game
    game = Game.new("Test Game", 4)
    {:ok, game_with_player1} = Game.add_player(game, player1)
    {:ok, game_with_players} = Game.add_player(game_with_player1, player2)
    {:ok, game_with_words} = Game.set_game_words(game_with_players, [word1, word2])
    {:ok, initialized_game} = Game.init_game(game_with_words)

    initialized_game = %{
      initialized_game
      | words: %{
          0 => GameWord.new(word1),
          1 => GameWord.new(word2)
        }
    }

    %{player: player1} = Map.get(initialized_game.players, 0)
    %{player: player2} = Map.get(initialized_game.players, 1)

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

  describe "give_up_player/2" do
    test "makes player give up successfully", %{game_state: game, player1: player} do
      {:ok, updated_game} = GameLogic.give_up_player(game, player)

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
      {:ok, updated_game} = GameLogic.give_up_player(initialized_game, player1)

      # Check that the current player is now Player 2
      assert %Player{id: current_player_id} = GameLogic.get_current_player(updated_game)
      assert current_player_id == player2.id
    end

    test "returns error when player not found", %{game_state: game} do
      unknown_player = Player.new("Unknown")
      assert {:error, :player_not_found} = GameLogic.give_up_player(game, unknown_player)
    end
  end

  describe "guess/3" do
    test "returns error when not player's turn", %{game_state: game_state, player2: player2} do
      # Player 2 tries to guess but it's player 1's turn
      assert {:error, :not_player_turn} = GameLogic.guess(game_state, "a", player2)
    end

    test "processes correct guess successfully", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'c' in 'cat'
      assert {:ok, updated_game} = GameLogic.guess(game_state, "c", player1)

      # Check that the guess was recorded
      current_word = get_current_word(updated_game)

      assert Enum.any?(current_word.guesses, fn guess ->
               guess.letter == "c" && guess.correct? == true
             end)

      # Player should get points for correct guess
      player = get_current_player(updated_game)
      assert player.score > 0
    end

    test "processes incorrect guess successfully", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'z' which is not in 'cat'
      assert {:ok, updated_game} = GameLogic.guess(game_state, "z", player1)

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
    end

    test "returns error for already guessed letter", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'c'
      {:ok, updated_game} = GameLogic.guess(game_state, "c", player1)

      # Player 1 tries to guess 'c' again
      assert {:error, :letter_already_guessed} = GameLogic.guess(updated_game, "c", player1)
    end

    test "returns error when game is not in playing status", %{
      game_state: game_state,
      player1: player1
    } do
      # Set game status to finished
      game_state = %{game_state | status: :finished}
      assert {:error, :game_not_playing} = GameLogic.guess(game_state, "a", player1)

      # Set game status to game_over
      game_state = %{game_state | status: :game_over}
      assert {:error, :game_not_playing} = GameLogic.guess(game_state, "a", player1)
    end
  end

  describe "game completion scenarios" do
    test "player completes a word and moves to next word", %{
      game_state: game_state,
      player1: player1
    } do
      # Player 1 guesses all letters in 'cat'
      {:ok, game_after_c} = GameLogic.guess(game_state, "c", player1)
      {:ok, game_after_a} = GameLogic.guess(game_after_c, "a", player1)
      {:ok, game_after_t} = GameLogic.guess(game_after_a, "t", player1)

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
      {:ok, game_after_c} = GameLogic.guess(game_state, "c", player1)
      {:ok, game_after_a} = GameLogic.guess(game_after_c, "a", player1)
      {:ok, game_after_t} = GameLogic.guess(game_after_a, "t", player1)

      # Complete second word 'dog'
      {:ok, game_after_d} = GameLogic.guess(game_after_t, "d", player1)
      {:ok, game_after_o} = GameLogic.guess(game_after_d, "o", player1)
      {:ok, game_after_g} = GameLogic.guess(game_after_o, "g", player1)

      # Game should be finished
      assert game_after_g.status == :finished
    end

    test "one player wins while another dies", %{
      game_state: game_state,
      player1: player1,
      player2: player2
    } do
      # Player 1 makes incorrect guesses and loses turn
      {:ok, game_after_z} = GameLogic.guess(game_state, "z", player1)

      # Now it's player 2's turn
      # Player 2 makes 6 incorrect guesses and dies
      {:ok, game_after_x} = GameLogic.guess(game_after_z, "x", player2)
      {:ok, game_after_v} = GameLogic.guess(game_after_x, "v", player1)
      {:ok, game_after_b} = GameLogic.guess(game_after_v, "b", player2)
      {:ok, game_after_n} = GameLogic.guess(game_after_b, "n", player1)
      {:ok, game_after_m} = GameLogic.guess(game_after_n, "m", player2)
      {:ok, game_after_q} = GameLogic.guess(game_after_m, "q", player1)
      {:ok, game_after_w} = GameLogic.guess(game_after_q, "w", player2)
      {:ok, game_after_e} = GameLogic.guess(game_after_w, "e", player1)
      {:ok, game_after_r} = GameLogic.guess(game_after_e, "r", player2)
      # Player 1 complete to earn more lives, and win player 2
      {:ok, game_after_c} = GameLogic.guess(game_after_r, "c", player1)
      {:ok, game_after_a} = GameLogic.guess(game_after_c, "a", player1)
      {:ok, game_after_t} = GameLogic.guess(game_after_a, "t", player1)
      # Player 2 loose in another word
      {:ok, game_after_x} = GameLogic.guess(game_after_t, "x", player1)
      {:ok, game_after_y} = GameLogic.guess(game_after_x, "y", player2)
      {:ok, game_after_z} = GameLogic.guess(game_after_y, "z", player1)
      {:ok, game_after_a} = GameLogic.guess(game_after_z, "a", player2)

      # Player 2 should be dead
      player2_state = get_player_by_id(game_after_a, player2.id)
      assert player2_state.status == :dead

      # Player 1 completes the words and wins
      {:ok, game_after_c} = GameLogic.guess(game_after_m, "c", player1)
      {:ok, game_after_a} = GameLogic.guess(game_after_c, "a", player1)
      {:ok, game_after_t} = GameLogic.guess(game_after_a, "t", player1)

      # Complete second word 'dog'
      {:ok, game_after_d} = GameLogic.guess(game_after_t, "d", player1)
      {:ok, game_after_o} = GameLogic.guess(game_after_d, "o", player1)
      {:ok, game_after_g} = GameLogic.guess(game_after_o, "g", player1)

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
      {:ok, game_after_z1} = GameLogic.guess(game_state, "z", player1)

      # Player 2 makes incorrect guesses
      {:ok, game_after_x1} = GameLogic.guess(game_after_z1, "x", player2)

      # Continue alternating incorrect guesses
      {:ok, game_after_v1} = GameLogic.guess(game_after_x1, "v", player1)
      {:ok, game_after_b1} = GameLogic.guess(game_after_v1, "b", player2)
      {:ok, game_after_n1} = GameLogic.guess(game_after_b1, "n", player1)
      {:ok, game_after_m1} = GameLogic.guess(game_after_n1, "m", player2)
      {:ok, game_after_q1} = GameLogic.guess(game_after_m1, "q", player1)
      {:ok, game_after_w1} = GameLogic.guess(game_after_q1, "w", player2)
      {:ok, game_after_e1} = GameLogic.guess(game_after_w1, "e", player1)
      {:ok, game_after_r1} = GameLogic.guess(game_after_e1, "r", player2)
      {:ok, game_after_y1} = GameLogic.guess(game_after_r1, "y", player1)
      {:ok, game_after_u1} = GameLogic.guess(game_after_y1, "u", player2)
      {:ok, game_after_i1} = GameLogic.guess(game_after_u1, "i", player1)
      {:ok, game_after_o1} = GameLogic.guess(game_after_i1, "o", player2)

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
      {:error, :not_player_turn} = GameLogic.guess(game_with_dead_player, "a", player1)

      # Try to guess with player 2
      assert {:ok, _game_} = GameLogic.guess(game_with_dead_player, "a", player2)
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
