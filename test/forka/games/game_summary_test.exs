defmodule Forka.Games.GameSummaryTest do
  use ExUnit.Case
  alias Forka.Games.{Game, Player, Word, GameSummary}
  alias Forka.Games.Game.GameWord

  setup do
    # Create a new game
    game = Game.new("Test Game", 4)

    # Add players
    player1 = Player.new("Player 1")
    player2 = Player.new("Player 2")
    {:ok, game_with_player1} = Game.add_player(game, player1)
    {:ok, game_with_players} = Game.add_player(game_with_player1, player2)

    # Set words
    words = [
      %Word{word: "cat", category: "Animals", hint: "Meows"},
      %Word{word: "dog", category: "Animals", hint: "Barks"}
    ]

    {:ok, game_with_words} = Game.set_game_words(game_with_players, words)
    {:ok, initialized_game} = Game.init_game(game_with_words)

    {:ok, lobby_game: game_with_words, initialized_game: initialized_game}
  end

  test "creates a game summary from lobby state", %{lobby_game: game_state} do
    summary = GameSummary.from_game_state(game_state)

    assert %GameSummary{} = summary
    assert summary.players == game_state.players
    assert summary.current_player_id == nil
    assert summary.guesses == []
    assert summary.remaining_words == nil
    assert summary.current_word_summary == nil
    assert summary.current_word_letters == nil
    assert summary.game_status == :lobby
  end

  test "creates a game summary from playing state", %{initialized_game: game_state} do
    summary = GameSummary.from_game_state(game_state)

    assert %GameSummary{} = summary
    assert summary.players == game_state.players

    assert summary.current_player_id ==
             game_state.players[game_state.current_game_player_index].player.id

    assert summary.guesses == game_state.words[game_state.current_game_word_index].guesses

    assert summary.remaining_words ==
             map_size(game_state.words) - game_state.current_game_word_index

    assert summary.current_word_summary.letters ==
             String.length(game_state.words[game_state.current_game_word_index].word.word)

    assert summary.current_word_summary.category ==
             game_state.words[game_state.current_game_word_index].word.category

    assert summary.current_word_letters ==
             GameWord.display_word_letters(game_state.words[game_state.current_game_word_index])

    assert summary.game_status == :playing
  end
end
