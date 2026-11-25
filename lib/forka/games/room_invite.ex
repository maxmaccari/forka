defmodule Forka.Games.RoomInvite do
  @moduledoc """
  Public invitation-safe read model for a room preview.
  """

  alias Forka.Games.Core.GameState
  alias Forka.Games.GameSummary
  alias Forka.Games.RoomListItem
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

  @doc "Builds a `%RoomInvite{}` from a `%GameSummary{}` and resolved category names."
  @spec from_game_summary(Ecto.UUID.t(), GameSummary.t(), [String.t()]) :: t()
  def from_game_summary(game_id, %GameSummary{} = summary, category_names)
      when is_list(category_names) do
    word_options = WordOptions.normalize(summary.word_options)
    player_count = map_size(summary.players)

    availability_state =
      RoomListItem.availability_state(%RoomListItem{
        id: game_id,
        status: summary.game_status,
        player_count: player_count,
        max_players: summary.max_players
      })

    %__MODULE__{
      id: game_id,
      name: summary.name,
      status: summary.game_status,
      availability_state: availability_state,
      max_players: summary.max_players,
      player_count: player_count,
      language: word_options.language,
      category_names: category_names,
      owner_username: (summary.owner && summary.owner.username) || ""
    }
  end
end
