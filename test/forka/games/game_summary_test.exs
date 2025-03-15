defmodule Forka.Games.GameSummaryTest do
  use ExUnit.Case, async: true
  alias Forka.Games.{Game, Player, Word, GameSummary}
  alias Forka.Games.Game.GameWord

  setup do
    # Create Owner
    owner = Player.new("owner")

    # Create a new game
    game = Game.new(owner, "Test Game", 4)

    # Add players
    player1 = Player.new("Player 1")
    player2 = Player.new("Player 2")
    {:ok, game_with_player1} = Game.join_game(game, player1)
    {:ok, game_with_players} = Game.join_game(game_with_player1, player2)

    # Set words
    words = [
      Word.new("cat", "animals", "Meows"),
      Word.new("dog", "animals", "Barks")
    ]

    game_with_words = Game.set_words(game_with_players, words)
    {:ok, initialized_game} = Game.start_game(game_with_words)

    {:ok, lobby_game: game_with_words, initialized_game: initialized_game}
  end

  test "creates a game summary from lobby state", %{lobby_game: game_state} do
    summary = GameSummary.from_game_state(game_state)

    assert %GameSummary{} = summary
    assert summary.players == game_state.players
    assert summary.owner == game_state.owner
    assert summary.current_player_id == nil
    assert summary.guesses == []
    assert summary.remaining_words == nil
    assert summary.current_word_summary == nil
    assert summary.current_word_letters == nil
    assert summary.game_status == :lobby
    assert summary.word_options == [language: "en"]
  end

  test "creates a game summary from playing state", %{initialized_game: game_state} do
    summary = GameSummary.from_game_state(game_state)

    assert %GameSummary{} = summary
    assert summary.players == game_state.players
    assert summary.owner == game_state.owner

    assert summary.current_player_id ==
             game_state.players[game_state.current_game_player_index].player.id

    assert summary.guesses == game_state.words[game_state.current_game_word_index].guesses

    assert summary.remaining_words ==
             map_size(game_state.words) - game_state.current_game_word_index

    assert summary.current_word_summary.letters ==
             Word.letters_count(game_state.words[game_state.current_game_word_index].word)

    assert summary.current_word_summary.category ==
             game_state.words[game_state.current_game_word_index].word.category

    assert summary.current_word_letters ==
             GameWord.display_word_letters(game_state.words[game_state.current_game_word_index])

    assert summary.game_status == :playing
    assert summary.last_event == game_state.last_event
    assert summary.word_options == [language: "en"]
  end

  test "creates a game summary and skips dead player", %{initialized_game: game_state} do
    # Mark the current player as dead
    current_player_index = game_state.current_game_player_index
    current_player = Map.get(game_state.players, current_player_index)
    dead_player = %{current_player | status: :dead, lives: 0}

    game_state = %{
      game_state
      | players: Map.put(game_state.players, current_player_index, dead_player)
    }

    # Create a game summary
    summary = GameSummary.from_game_state(game_state)

    # Ensure the summary skips the dead player and selects the next player
    next_player_index = rem(current_player_index + 1, map_size(game_state.players))
    next_player = Map.get(game_state.players, next_player_index)

    assert %GameSummary{} = summary
    assert summary.players == game_state.players
    assert summary.current_player_id == next_player.player.id
    assert summary.guesses == game_state.words[game_state.current_game_word_index].guesses

    assert summary.remaining_words ==
             map_size(game_state.words) - game_state.current_game_word_index

    assert summary.current_word_summary.letters ==
             Word.letters_count(game_state.words[game_state.current_game_word_index].word)

    assert summary.current_word_summary.category ==
             Word.category(game_state.words[game_state.current_game_word_index].word)

    assert summary.current_word_letters ==
             GameWord.display_word_letters(game_state.words[game_state.current_game_word_index])

    assert summary.game_status == :playing
    assert summary.last_event == game_state.last_event
  end

  test "creates a game summary for game_over state", %{initialized_game: game_state} do
    # Set game to game_over state
    game_over_state = %{
      game_state
      | status: :game_over,
        current_game_player_index: nil,
        current_game_word_index: nil
    }

    summary = GameSummary.from_game_state(game_over_state)

    assert %GameSummary{} = summary
    assert summary.players == game_over_state.players
    assert summary.owner == game_over_state.owner
    assert summary.current_player_id == nil
    assert summary.game_status == :game_over
  end

  test "creates a game summary for finished state", %{initialized_game: game_state} do
    # Set game to finished state
    finished_state = %{
      game_state
      | status: :finished,
        current_game_player_index: nil,
        current_game_word_index: nil
    }

    summary = GameSummary.from_game_state(finished_state)

    assert %GameSummary{} = summary
    assert summary.players == finished_state.players
    assert summary.owner == finished_state.owner
    assert summary.current_player_id == nil
    assert summary.game_status == :finished
  end

  test "creates a game summary for archived state", %{initialized_game: game_state} do
    # Set game to archived state
    archived_state = %{game_state | status: :archived, last_event: :game_archived}

    summary = GameSummary.from_game_state(archived_state)

    assert %GameSummary{} = summary
    assert summary.players == archived_state.players
    assert summary.owner == archived_state.owner
    assert summary.game_status == :archived
    assert summary.last_event == :game_archived
  end
end
