defmodule Forka.Games.GameSummary do
  alias Forka.Games.Game.{GameState, GamePlayer, GameWord}
  alias Forka.Games.GameSummary.WordSummary

  defstruct players: %{},
            current_player_id: nil,
            guesses: [],
            remaining_words: nil,
            current_word_summary: nil,
            current_word_letters: nil,
            game_status: nil

  def from_game_state(%GameState{
        status: :lobby,
        players: players
      }) do
    %__MODULE__{
      players: players,
      game_status: :lobby
    }
  end

  def from_game_state(%GameState{
        players: players,
        current_game_player_index: player_index,
        words: words,
        current_game_word_index: word_index,
        status: status
      }) do
    %GamePlayer{player: player} = Map.get(players, player_index)
    %GameWord{guesses: guesses, word: word} = game_word = Map.get(words, word_index)
    remaining_words = map_size(words) - word_index
    current_word_letters = GameWord.display_word_letters(game_word)

    %__MODULE__{
      players: players,
      current_player_id: player.id,
      guesses: guesses,
      remaining_words: remaining_words,
      current_word_summary: WordSummary.from_word(word),
      current_word_letters: current_word_letters,
      game_status: status
    }
  end
end
