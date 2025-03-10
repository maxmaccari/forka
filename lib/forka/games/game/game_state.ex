defmodule Forka.Games.Game.GameState do
  @moduledoc """
  Represents the state of a Forka (Hangman) game session.

  A GameState holds all information about an ongoing game including:
  - Unique identifier
  - Game name
  - Words being played (as a map of GameWord structs)
  - Players participating (as a map of GamePlayer structs)
  - Current word and player indices
  - Game status (:lobby, :playing, :finished)
  - Maximum number of allowed players

  The game starts in :lobby status where players can join/leave.
  Once started, it tracks the current word being guessed and which
  player's turn it is.
  """

  # TODO: In the future, this will be an Ecto module referencing to "games" table

  defstruct id: nil,
            name: nil,
            words: %{},
            players: %{},
            current_game_word_index: nil,
            current_game_player_index: nil,
            status: :lobby,
            max_players: 0
end
