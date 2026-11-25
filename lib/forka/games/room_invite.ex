defmodule Forka.Games.RoomInvite do
  @moduledoc """
  Public invitation-safe read model for a room preview.
  """

  alias Forka.Games.Core.GameState
  alias Forka.Games.RoomListItem
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.WordOptions

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          status: GameState.status(),
          availability_state: RoomListItem.availability(),
          max_players: pos_integer(),
          player_count: non_neg_integer(),
          language: String.t(),
          category_names: [String.t()],
          owner_username: String.t()
        }

  defstruct [
    :id,
    :name,
    :status,
    :availability_state,
    :max_players,
    :player_count,
    :language,
    :category_names,
    :owner_username
  ]

  @doc "Builds a `%RoomInvite{}` from persisted room metadata and resolved category names."
  @spec from_game(Game.t(), non_neg_integer(), String.t() | nil, [String.t()]) :: t()
  def from_game(%Game{} = game, player_count, owner_username, category_names)
      when is_integer(player_count) and player_count >= 0 and is_list(category_names) do
    word_options = WordOptions.normalize(game.word_options)

    availability_state =
      RoomListItem.availability_state(%RoomListItem{
        id: game.id,
        status: game.status,
        player_count: player_count,
        max_players: game.max_players
      })

    %__MODULE__{
      id: game.id,
      name: game.name,
      status: game.status,
      availability_state: availability_state,
      max_players: game.max_players,
      player_count: player_count,
      language: word_options.language,
      category_names: category_names,
      owner_username: owner_username || ""
    }
  end
end
