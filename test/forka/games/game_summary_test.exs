defmodule Forka.Games.GameSummaryTest do
  use ExUnit.Case, async: true
  alias Forka.Games.Core
  alias Forka.Games.GameSummary
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Word

  import Forka.TestHelpers

  setup do
    # Create Owner
    owner = build_games_player("owner")

    # Create a new game
    game = Core.new(owner, "Test Game", 4)

    # Add players
    player1 = build_games_player("Player 1")
    player2 = build_games_player("Player 2")
    {:ok, game_with_player1} = Core.join_game(game, player1)
    {:ok, game_with_players} = Core.join_game(game_with_player1, player2)

    # Set words
    words = [
      Word.new("cat", "animals", "Meows"),
      Word.new("dog", "animals", "Barks")
    ]

    game_with_words = Core.set_words(game_with_players, words)
    {:ok, initialized_game} = Core.start_game(game_with_words)

    {:ok, lobby_game: game_with_words, initialized_game: initialized_game}
  end

  test "creates a game summary from lobby state", %{lobby_game: game_state} do
    summary = GameSummary.from_game_state(game_state)

    assert %GameSummary{} = summary
    assert summary.players == game_state.game_players
    assert summary.owner == game_state.owner
    assert summary.current_player_id == nil
    assert summary.guesses == []
    assert summary.remaining_words == nil
    assert summary.current_word_summary == nil
    assert summary.current_word_letters == nil
    assert summary.game_status == :lobby
    assert summary.word_options == [language: "en"]

    assert is_list(summary.last_events)
    assert Enum.all?(summary.last_events, fn event -> event.tick == game_state.tick end)
  end

  test "creates a game summary from playing state", %{initialized_game: game_state} do
    summary = GameSummary.from_game_state(game_state)

    assert %GameSummary{} = summary
    assert summary.players == game_state.game_players
    assert summary.owner == game_state.owner

    assert summary.current_player_id ==
             game_state.game_players[game_state.current_game_player_index].player.id

    assert summary.guesses == game_state.game_words[game_state.current_game_word_index].guesses

    assert summary.remaining_words ==
             map_size(game_state.game_words) - game_state.current_game_word_index

    assert summary.current_word_summary.letters ==
             Word.letters_count(game_state.game_words[game_state.current_game_word_index].word)

    assert summary.current_word_summary.category ==
             game_state.game_words[game_state.current_game_word_index].word.category

    assert summary.current_word_letters ==
             GameWord.display_word_letters(
               game_state.game_words[game_state.current_game_word_index]
             )

    assert summary.game_status == :playing
    assert summary.word_options == [language: "en"]

    assert is_list(summary.last_events)
    assert Enum.all?(summary.last_events, fn event -> event.tick == game_state.tick end)
  end

  test "creates a game summary and skips dead player", %{initialized_game: game_state} do
    # Mark the current player as dead
    current_player_index = game_state.current_game_player_index
    current_player = Map.get(game_state.game_players, current_player_index)
    dead_player = %{current_player | status: :dead, lives: 0}

    game_state = %{
      game_state
      | game_players: Map.put(game_state.game_players, current_player_index, dead_player)
    }

    # Create a game summary
    summary = GameSummary.from_game_state(game_state)

    # Ensure the summary skips the dead player and selects the next player
    next_player_index = rem(current_player_index + 1, map_size(game_state.game_players))
    next_player = Map.get(game_state.game_players, next_player_index)

    assert %GameSummary{} = summary
    assert summary.players == game_state.game_players
    assert summary.current_player_id == next_player.player.id
    assert summary.guesses == game_state.game_words[game_state.current_game_word_index].guesses

    assert summary.remaining_words ==
             map_size(game_state.game_words) - game_state.current_game_word_index

    assert summary.current_word_summary.letters ==
             Word.letters_count(game_state.game_words[game_state.current_game_word_index].word)

    assert summary.current_word_summary.category ==
             Word.category(game_state.game_words[game_state.current_game_word_index].word)

    assert summary.current_word_letters ==
             GameWord.display_word_letters(
               game_state.game_words[game_state.current_game_word_index]
             )

    assert summary.game_status == :playing
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
    assert summary.players == game_over_state.game_players
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
    assert summary.players == finished_state.game_players
    assert summary.owner == finished_state.owner
    assert summary.current_player_id == nil
    assert summary.game_status == :finished
  end

  test "creates a game summary for archived state", %{initialized_game: game_state} do
    # Set game to archived state
    archived_state = %{game_state | status: :archived}

    summary = GameSummary.from_game_state(archived_state)

    assert %GameSummary{} = summary
    assert summary.players == archived_state.game_players
    assert summary.owner == archived_state.owner
    assert summary.game_status == :archived
  end

  test "loads all events when load_all_events option is set to true", %{
    initialized_game: game_state
  } do
    # Add some events to the game state
    events = [
      %{type: "player_joined", payload: %{player_id: "player1"}, tick: 1},
      %{type: "game_started", payload: %{}, tick: 2},
      %{type: "letter_guessed", payload: %{letter: "a"}, tick: 3}
    ]

    game_state_with_events = %{game_state | events: events, tick: 3}

    # Get summary with default options (only current tick events)
    default_summary = GameSummary.from_game_state(game_state_with_events)

    # Get summary with load_all_events option
    all_events_summary =
      GameSummary.from_game_state(game_state_with_events, load_all_events: true)

    # Default should only have events from current tick (3)
    assert length(default_summary.last_events) ==
             Enum.count(events, fn event -> event.tick == 3 end)

    # With load_all_events, should have all events
    assert length(all_events_summary.last_events) == length(events)
    assert all_events_summary.last_events == events
  end
end
