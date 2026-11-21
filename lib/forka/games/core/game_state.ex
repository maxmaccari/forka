defmodule Forka.Games.Core.GameState do
  @moduledoc """
  Represents the state of a Forka (Hangman) game session.

  A GameState holds all information about an ongoing game including:
  - Unique identifier
  - Game name
  - Words being played (as a map of GameWord structs in the game_words field)
  - Players participating (as a map of GamePlayer structs in the game_players field)
  - Current word and player indices
  - Game status (:lobby, :playing, :finished, :archived)
  - Maximum number of allowed players
  - Game owner (the player who created the game)
  - Last event that occurred in the game
  - Word options for filtering words (language, category_ids)

  The game starts in :lobby status where players can join/leave.
  Once started, it tracks the current word being guessed and which
  player's turn it is. When all players give up or the game is completed,
  it transitions to :finished status. Games can also be archived.
  """

  alias Forka.Games.Schemas.{Event, GamePlayer, GameWord, Player, WordOptions}

  @type status :: :lobby | :playing | :finished | :archived | :game_over
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          game_words: %{non_neg_integer() => GameWord.t()},
          game_players: %{non_neg_integer() => GamePlayer.t()},
          owner: Player.t() | Ecto.Association.NotLoaded.t() | nil,
          current_game_word_index: non_neg_integer() | nil,
          current_game_player_index: non_neg_integer() | nil,
          status: status(),
          max_players: integer() | nil,
          word_options: WordOptions.t() | keyword() | nil,
          tick: non_neg_integer(),
          events: [Event.t()] | Ecto.Association.NotLoaded.t()
        }

  defstruct id: nil,
            name: nil,
            game_words: %{},
            game_players: %{},
            owner: nil,
            current_game_word_index: nil,
            current_game_player_index: nil,
            status: :lobby,
            max_players: 0,
            word_options: [language: "en"],
            tick: 0,
            events: []
end
