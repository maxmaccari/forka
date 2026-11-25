defmodule Forka.Games.Core.GameLogicTest do
  use ExUnit.Case, async: true
  alias Forka.Games.Core
  alias Forka.Games.Core.{GameLogic, GameState}
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.Word

  import Forka.Games.Core.Helpers
  import Forka.TestHelpers

  @tag audit_f06: true
  test "F-06 a surrender at the last position passes the turn to a surviving player", %{
    game_state: game,
    player1: first,
    player2: last
  } do
    assert {:ok, game} = GameLogic.guess(game, first.id, "z")
    assert game.current_game_player_index == 1
    assert {:ok, game} = GameLogic.give_up_game(game, last.id)
    assert game.status == :playing
    assert game.current_game_player_index == 0
    assert GameLogic.get_current_player(game).id == first.id
    assert %{status: :dead, lives: 0} = game.game_players[1]
    assert [%{type: :next_player_turn}, %{type: :player_gave_up} | _] = game.events
  end

  @tag audit_f06: true
  test "F-06 reading and taking the turn wrap past a stored dead player", %{
    game_state: game,
    player1: first,
    player2: last
  } do
    game = %{
      game
      | current_game_player_index: 1,
        game_players: Map.update!(game.game_players, 1, &GamePlayer.give_up/1)
    }

    assert GameLogic.get_current_player(game) == first
    assert GameLogic.guess(game, last.id, "a") == {:error, :not_player_turn}
    assert {:ok, game} = GameLogic.guess(game, first.id, "a")
    assert game.current_game_player_index == 0
    assert game.game_players[0].score == 10
  end

  test "turn recovery and its accepted guess share a tick", %{game_state: game, player1: first} do
    game = %{
      game
      | current_game_player_index: 1,
        game_players: Map.update!(game.game_players, 1, &GamePlayer.give_up/1)
    }

    assert {:ok, recovered} = GameLogic.guess(game, first.id, "a")

    assert Enum.map(Core.to_game_summary(recovered).last_events, & &1.type) ==
             [:player_scored, :player_guessed, :next_player_turn]
  end

  setup do
    # Create owner
    owner = build_games_player("Owner")

    # Create players
    player1 = build_games_player("Player 1")
    player2 = build_games_player("Player 2")

    # Create words
    word1 = Word.new("cat", "animals", "Meows")
    word2 = Word.new("dog", "animals", "Barks")

    # Create a game
    game = Core.new(owner, "Test Game", 4)
    {:ok, game_with_player1} = Core.join_game(game, player1)
    {:ok, game_with_players} = Core.join_game(game_with_player1, player2)
    game_with_words = Core.set_words(game_with_players, [word1, word2])
    {:ok, initialized_game} = Core.start_game(game_with_words, owner.id)

    {:ok,
     game_state: initialized_game, player1: player1, player2: player2, word1: word1, word2: word2}
  end

  describe "get_current_player/1" do
    test "returns the current player", %{game_state: game, player1: player1} do
      assert %Player{id: player_id} = Core.get_current_player(game)
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
        | game_players: %{
            0 => %GamePlayer{player: player1, status: :dead},
            1 => %GamePlayer{player: player2, status: :alive}
          },
          current_game_player_index: 0
      }

      # Get the current player, which should now be player2
      assert %Player{id: player_id} = Core.get_current_player(game_with_dead_player1)
      assert player_id == player2.id
    end

    test "returns error when no current player", %{game_state: game} do
      game_without_players = %{game | game_players: %{}, current_game_player_index: nil}
      assert Core.get_current_player(game_without_players) == nil
    end
  end

  describe "give_up_game/2" do
    test "makes player give up successfully", %{game_state: game, player1: player} do
      {:ok, updated_game} = GameLogic.give_up_game(game, player.id)

      assert updated_game.tick == game.tick + 1

      assert_last_events(updated_game, [
        %{type: :next_player_turn},
        %{type: :player_gave_up, payload: %{player_id: player.id}}
      ])

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

      assert_last_events(updated_game, [
        %{type: :next_player_turn, payload: %{player_id: current_player_id}},
        %{type: :player_gave_up, payload: %{player_id: player1.id}}
      ])
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

      assert_last_events(game_after_p2, [
        %{type: :game_over},
        %{type: :player_gave_up, payload: %{player_id: player2.id}}
      ])
    end

    test "REQ-01: returns {:error, :not_a_participant} when non-member tries to give up in playing or lobby",
         %{game_state: game} do
      unknown_player = build_games_player("Unknown")
      assert {:error, :not_a_participant} = GameLogic.give_up_game(game, unknown_player.id)

      lobby_game = %{game | status: :lobby}
      assert {:error, :not_a_participant} = GameLogic.give_up_game(lobby_game, unknown_player.id)
    end

    test "REQ-01: returns {:error, :game_not_playing} when seated member tries to give up outside playing",
         %{game_state: game, player1: player1} do
      for status <- [:lobby, :finished, :game_over] do
        assert {:error, :game_not_playing} =
                 GameLogic.give_up_game(%{game | status: status}, player1.id)
      end
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

    test "REQ-01: returns {:error, :not_a_participant} when non-member tries to guess in playing or lobby",
         %{game_state: game_state} do
      outsider = build_games_player("Outsider")
      assert {:error, :not_a_participant} = GameLogic.guess(game_state, outsider.id, "a")

      lobby_game = %{game_state | status: :lobby}
      assert {:error, :not_a_participant} = GameLogic.guess(lobby_game, outsider.id, "a")
    end

    test "processes correct guess successfully", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'c' in 'cat'
      assert {:ok, updated_game} = GameLogic.guess(game_state, player1.id, "c")

      # Check that the guess was recorded
      current_word = get_current_game_word(updated_game)

      assert Enum.any?(current_word.guesses, fn guess ->
               guess.letter == "c" && guess.correct? == true
             end)

      # Player should get points for correct guess
      game_player = get_current_game_player(updated_game)
      assert game_player.score > 0

      # Check if correct guess was processed correctly
      [guess] = current_word.guesses

      # Check that the events were generated correctly
      assert_last_events(updated_game, [
        %{type: :player_scored, payload: %{player_id: player1.id}},
        %{
          type: :player_guessed,
          payload: %{player_id: player1.id, letter: guess.letter, correct?: guess.correct?}
        }
      ])
    end

    test "processes incorrect guess successfully", %{game_state: game_state, player1: player1} do
      # Player 1 guesses 'z' which is not in 'cat'
      assert {:ok, updated_game} = GameLogic.guess(game_state, player1.id, "z")

      # Check that the guess was recorded
      current_word = get_current_game_word(updated_game)

      assert Enum.any?(current_word.guesses, fn guess ->
               guess.letter == "z" && guess.correct? == false
             end)

      # Player should lose a life
      player = get_player_by_id(updated_game, player1.id)
      assert player.lives == 5

      # Turn should move to next player
      current_player = get_current_game_player(updated_game)
      refute current_player.player.id == player1.id

      # Check that the events were generated correctly
      assert_last_events(updated_game, [
        %{type: :next_player_turn, payload: %{player_id: current_player.player.id}},
        %{type: :player_lost_life, payload: %{player_id: player1.id}},
        %{type: :player_guessed, payload: %{player_id: player1.id, letter: "z", correct?: false}}
      ])
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

      # Check that the events were pushed correctly
      assert_last_events(game_after_t, [
        %{type: :player_guessed},
        %{type: :player_scored},
        %{type: :word_completed, payload: %{player_id: player1.id}},
        %{type: :moved_to_next_word}
      ])
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

      # Check that the game finished event was pushed
      assert_last_events(game_after_g, [
        %{type: :player_guessed},
        %{type: :player_scored},
        %{type: :word_completed},
        %{type: :game_finished}
      ])

      # Verify the final state
      assert game_after_g.current_game_word_index == 1
      assert game_after_g.current_game_player_index == 0

      # Check player's final score
      player = get_player_by_id(game_after_g, player1.id)
      # Should have points from both words
      assert player.score > 60
    end

    @tag audit_f07: true
    test "F-07 the sixth miss eliminates a player and the survivor can win", %{
      game_state: game,
      player1: survivor,
      player2: eliminated
    } do
      guesses = [
        {survivor.id, "z"},
        {eliminated.id, "x"},
        {survivor.id, "v"},
        {eliminated.id, "b"},
        {survivor.id, "n"},
        {eliminated.id, "m"},
        {survivor.id, "q"},
        {eliminated.id, "w"},
        {survivor.id, "e"},
        {eliminated.id, "r"},
        {survivor.id, "c"},
        {survivor.id, "a"},
        {survivor.id, "t"},
        {survivor.id, "x"}
      ]

      game =
        Enum.reduce(guesses, game, fn {player_id, letter}, state ->
          assert {:ok, updated} = GameLogic.guess(state, player_id, letter)
          updated
        end)

      assert %{status: :alive, lives: 1} = game.game_players[1]
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "y")
      assert %{status: :dead, lives: 0} = game.game_players[1]
      assert game.status == :playing
      assert game.current_game_player_index == 0
      assert [%{type: :next_player_turn}, %{type: :player_died} | _] = game.events

      assert {:ok, game} = GameLogic.guess(game, survivor.id, "d")
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "o")
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "g")
      assert game.status == :finished
      assert game.game_players[0].score == 120
      assert game.game_players[1].score == 0
    end

    @tag audit_f07: true
    test "F-07 twelve alternating misses eliminate both players and end the match", %{
      game_state: game,
      player1: first,
      player2: second
    } do
      guesses = [
        {first.id, "z"},
        {second.id, "x"},
        {first.id, "v"},
        {second.id, "b"},
        {first.id, "n"},
        {second.id, "m"},
        {first.id, "q"},
        {second.id, "w"},
        {first.id, "e"},
        {second.id, "r"},
        {first.id, "y"},
        {second.id, "u"}
      ]

      game =
        Enum.reduce(guesses, game, fn {player_id, letter}, state ->
          assert {:ok, updated} = GameLogic.guess(state, player_id, letter)
          updated
        end)

      assert game.status == :game_over
      assert game.current_game_player_index == nil
      assert game.current_game_word_index == nil
      assert %{status: :dead, lives: 0} = game.game_players[0]
      assert %{status: :dead, lives: 0} = game.game_players[1]

      assert [%{type: :game_over}, %{type: :player_died}, %{type: :player_guessed} | _] =
               game.events
    end

    test "R-02: sixth miss locks a non-zero score across words and ends in game_over when last survivor falls",
         %{
           game_state: game,
           player1: survivor,
           player2: eliminated
         } do
      # Player 1 misses once (turn -> Player 2), Player 2 scores 20 pts ('c', 'a') then misses 6 times
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "z")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "c")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "a")
      assert game.game_players[1].score == 20

      # Five misses for Player 2 (alternating with Player 1, who stays alive and finishes word 1)
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "x")
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "v")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "b")
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "n")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "m")
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "q")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "w")
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "e")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "r")

      # Player 2 is down to 1 life; Player 1 finishes word 1 ('t') and heals to 6 lives
      assert %{status: :alive, lives: 1, score: 20} = game.game_players[1]
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "t")
      assert game.current_game_word_index == 1
      assert %{status: :alive, lives: 6, score: 40} = game.game_players[0]
      assert %{status: :alive, lives: 1, score: 20} = game.game_players[1]

      # Word 2 ("dog"): Player 1 misses once (turn -> Player 2), Player 2 takes 6th miss
      assert {:ok, game} = GameLogic.guess(game, survivor.id, "z")
      assert {:ok, game} = GameLogic.guess(game, eliminated.id, "x")

      assert %{status: :dead, lives: 0, score: 20} = game.game_players[1]
      assert game.status == :playing
      assert game.current_game_player_index == 0
      assert GameLogic.guess(game, eliminated.id, "d") == {:error, :not_player_turn}

      # Player 1 takes 5 more misses on word 2 (total 6 since heal) -> everyone out -> :game_over
      game =
        Enum.reduce(["v", "b", "n", "m", "q"], game, fn letter, state ->
          assert {:ok, updated} = GameLogic.guess(state, survivor.id, letter)
          updated
        end)

      assert game.status == :game_over
      assert game.current_game_player_index == nil
      assert game.current_game_word_index == nil
      assert %{status: :dead, lives: 0, score: 40} = game.game_players[0]
      assert %{status: :dead, lives: 0, score: 20} = game.game_players[1]

      assert [%{type: :game_over}, %{type: :player_died}, %{type: :player_guessed} | _] =
               game.events
    end
  end

  describe "edge cases" do
    test "player automatically skipped when dead", %{
      game_state: game_state,
      player1: player1,
      player2: player2
    } do
      player_index = game_state.current_game_player_index
      game_player = Map.get(game_state.game_players, player_index)
      dead_player = %{game_player | status: :dead, lives: 0}

      game_with_dead_player = %{
        game_state
        | game_players: Map.put(game_state.game_players, player_index, dead_player)
      }

      # Try to guess with player 1 (who is now dead)
      {:error, :not_player_turn} = GameLogic.guess(game_with_dead_player, player1.id, "a")

      # Try to guess with player 2
      assert {:ok, _game_} = GameLogic.guess(game_with_dead_player, player2.id, "a")
    end
  end

  # Helper functions
  defp get_current_game_word(%GameState{game_words: game_words, current_game_word_index: index}) do
    Map.get(game_words, index)
  end

  defp get_current_game_player(%GameState{
         game_players: game_players,
         current_game_player_index: index
       }) do
    Map.get(game_players, index)
  end

  defp get_player_by_id(%GameState{game_players: game_players}, player_id) do
    {_idx, player} =
      Enum.find(game_players, fn {_idx, game_player} ->
        game_player.player.id == player_id
      end)

    player
  end
end
