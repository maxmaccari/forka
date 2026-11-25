defmodule Forka.Games.RoomLobby do
  @moduledoc """
  Lobby-safe read model projected for an authenticated viewer.
  """

  alias Forka.Games.Core.GameState
  alias Forka.Games.GameSummary
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Players.Player, as: AuthPlayer
  alias Forka.Scope

  @type player_entry :: %{id: Ecto.UUID.t(), username: String.t()}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          status: GameState.status(),
          max_players: integer(),
          player_count: non_neg_integer(),
          language: String.t(),
          category_names: [String.t()],
          owner_username: String.t(),
          players: [player_entry()],
          can_edit_settings?: boolean()
        }

  defstruct [
    :id,
    :name,
    :status,
    :max_players,
    :player_count,
    :language,
    :category_names,
    :owner_username,
    :players,
    :can_edit_settings?
  ]

  @doc "Builds a lobby-safe PubSub payload from a `%GameState{}`."
  @spec payload(GameState.t(), [String.t()]) :: map()
  def payload(%GameState{} = state, category_names) when is_list(category_names) do
    word_options = WordOptions.normalize(state.word_options)

    %{
      id: state.id,
      name: state.name,
      status: state.status,
      max_players: state.max_players,
      player_count: map_size(state.game_players),
      language: word_options.language,
      category_names: category_names,
      owner_id: state.owner && state.owner.id,
      owner_username: (state.owner && state.owner.username) || "",
      players: players_from_map(state.game_players)
    }
  end

  @doc "Projects a `%RoomLobby{}` from a lobby PubSub payload for the given viewer scope."
  @spec from_payload(Scope.t(), map()) :: t()
  def from_payload(%Scope{player: %AuthPlayer{id: viewer_id}}, payload) when is_map(payload) do
    %__MODULE__{
      id: payload.id,
      name: payload.name,
      status: payload.status,
      max_players: payload.max_players,
      player_count: payload.player_count,
      language: payload.language,
      category_names: payload.category_names,
      owner_username: payload.owner_username,
      players: payload.players,
      can_edit_settings?: payload.status == :lobby and payload.owner_id == viewer_id
    }
  end

  @doc "Projects a `%RoomLobby{}` from a `%GameSummary{}` for the given viewer scope."
  @spec from_game_summary(Scope.t(), Ecto.UUID.t(), GameSummary.t(), [String.t()]) :: t()
  def from_game_summary(
        %Scope{player: %AuthPlayer{id: viewer_id}},
        game_id,
        %GameSummary{} = summary,
        category_names
      )
      when is_list(category_names) do
    word_options = WordOptions.normalize(summary.word_options)

    %__MODULE__{
      id: game_id,
      name: summary.name,
      status: summary.game_status,
      max_players: summary.max_players,
      player_count: map_size(summary.players),
      language: word_options.language,
      category_names: category_names,
      owner_username: (summary.owner && summary.owner.username) || "",
      players: players_from_map(summary.players),
      can_edit_settings?:
        summary.game_status == :lobby and not is_nil(summary.owner) and
          summary.owner.id == viewer_id
    }
  end

  defp players_from_map(players_map) when is_map(players_map) do
    players_map
    |> Enum.sort_by(fn {pos, _gp} -> pos end)
    |> Enum.map(fn {_pos, gp} ->
      %{id: gp.player.id, username: gp.player.username}
    end)
  end
end
