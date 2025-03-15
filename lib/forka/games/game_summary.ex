defmodule Forka.Games.GameSummary do
  @moduledoc """
  This module provides a summary representation of a game state, containing only non-sensitive information
  that can be safely shared with players.

  Each GameSummary has:
  - A map of players in the game
  - The ID of the current player's turn
  - List of guesses made for the current word
  - Number of remaining words to guess
  - A WordSummary of the current word being guessed
  - Display state of the current word's letters
  - Current game status (:lobby or :playing)

  This module is used to safely share game state information with players without revealing
  sensitive details like the actual words being guessed.
  """

  alias Forka.Games.Game
  alias Forka.Games.Game.{GameState, GameWord}
  alias Forka.Games.GameSummary.WordSummary

  defstruct players: %{},
            current_player_id: nil,
            owner: nil,
            guesses: [],
            remaining_words: nil,
            current_word_summary: nil,
            current_word_letters: nil,
            game_status: nil

  @doc """
  Creates a GameSummary from a GameState.

  ## Parameters
    - game_state: A GameState struct in either :lobby or :playing status

  ## Returns
  A GameSummary struct containing the current game state information that is safe to share with players.
  When in :lobby status, only includes basic game information.
  When in :playing status, includes additional game progress information.
  """
  def from_game_state(
        %GameState{
          players: players,
          owner: owner,
          words: words,
          current_game_word_index: word_index,
          status: :playing
        } = game_state
      ) do
    current_player = Game.get_current_player(game_state)

    %GameWord{guesses: guesses, word: word} = game_word = Map.get(words, word_index)
    remaining_words = map_size(words) - word_index
    current_word_letters = GameWord.display_word_letters(game_word)

    %__MODULE__{
      players: players,
      owner: owner,
      current_player_id: current_player && current_player.id,
      guesses: guesses,
      remaining_words: remaining_words,
      current_word_summary: WordSummary.from_word(word),
      current_word_letters: current_word_letters,
      game_status: :playing
    }
  end

  def from_game_state(%GameState{
        status: status,
        players: players,
        owner: owner
      }) do
    %__MODULE__{
      players: players,
      owner: owner,
      game_status: status
    }
  end
end
