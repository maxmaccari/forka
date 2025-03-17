defmodule Forka.Games.Game.GameState do
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

  # TODO: In the future, this will be an Ecto module referencing to "games" table

  defstruct id: nil,
            name: nil,
            game_words: %{},
            game_players: %{},
            owner: nil,
            current_game_word_index: nil,
            current_game_player_index: nil,
            status: :lobby,
            max_players: 0,
            last_event: nil,
            word_options: [language: "en"]
end
