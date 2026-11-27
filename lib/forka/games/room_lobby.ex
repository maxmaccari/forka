defmodule Forka.Games.RoomLobby do
  @moduledoc """
  Lobby-safe read model projected for an authenticated viewer.
  """

  alias Forka.Games.Core.GameState
  alias Forka.Games.GameSummary
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Games.WordAvailability
  alias Forka.Players.Player, as: AuthPlayer
  alias Forka.Scope

  @type player_entry :: %{id: Ecto.UUID.t(), username: String.t()}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          status: GameState.status(),
          max_players: integer(),
          player_count: non_neg_integer(),
          empty_seats: non_neg_integer(),
          language: String.t(),
          category_names: [String.t()],
          owner_id: Ecto.UUID.t() | nil,
          owner_username: String.t(),
          players: [player_entry()],
          is_owner?: boolean(),
          participant?: boolean(),
          can_edit_settings?: boolean(),
          can_leave?: boolean(),
          can_transfer_ownership?: boolean(),
          word_availability: WordAvailability.t() | nil
        }

  defstruct [
    :id,
    :name,
    :status,
    :max_players,
    :player_count,
    :empty_seats,
    :language,
    :category_names,
    :owner_id,
    :owner_username,
    :players,
    :is_owner?,
    :participant?,
    :can_edit_settings?,
    :can_leave?,
    :can_transfer_ownership?,
    :word_availability
  ]

  @doc "Builds a lobby-safe PubSub payload from a `%GameState{}`."
  @spec payload(GameState.t(), [String.t()], non_neg_integer() | nil) :: map()
  def payload(%GameState{} = state, category_names, available_words \\ nil)
      when is_list(category_names) do
    word_options = WordOptions.normalize(state.word_options)

    %{
      id: state.id,
      name: state.name,
      status: state.status,
      max_players: state.max_players,
      player_count: map_size(state.game_players),
      language: word_options.language,
      category_names: category_names,
      has_category_filter?: word_options.category_ids != [],
      available_words: available_words,
      owner_id: state.owner && state.owner.id,
      owner_username: (state.owner && state.owner.username) || "",
      players: players_from_map(state.game_players)
    }
  end

  @doc "Projects a `%RoomLobby{}` from a lobby PubSub payload for the given viewer scope."
  @spec from_payload(Scope.t(), map()) :: t()
  def from_payload(%Scope{player: %AuthPlayer{id: viewer_id}}, payload) when is_map(payload) do
    owner_id = payload.owner_id
    players = payload.players
    is_owner? = not is_nil(owner_id) and owner_id == viewer_id
    participant? = participant_in_entries?(players, viewer_id)

    %__MODULE__{
      id: payload.id,
      name: payload.name,
      status: payload.status,
      max_players: payload.max_players,
      player_count: payload.player_count,
      empty_seats: max(payload.max_players - payload.player_count, 0),
      language: payload.language,
      category_names: payload.category_names,
      owner_id: owner_id,
      owner_username: payload.owner_username,
      players: players,
      is_owner?: is_owner?,
      participant?: participant?,
      can_edit_settings?: payload.status == :lobby and is_owner?,
      can_leave?: payload.status == :lobby and participant?,
      can_transfer_ownership?: payload.status == :lobby and is_owner?,
      word_availability:
        build_word_availability(
          payload.status,
          Map.get(payload, :available_words),
          payload.player_count,
          payload.max_players,
          payload.language,
          Map.get(payload, :has_category_filter?, payload.category_names != [])
        )
    }
  end

  @doc "Projects a `%RoomLobby{}` from a `%GameSummary{}` for the given viewer scope."
  @spec from_game_summary(
          Scope.t(),
          Ecto.UUID.t(),
          GameSummary.t(),
          [String.t()],
          non_neg_integer() | nil
        ) :: t()
  def from_game_summary(
        %Scope{player: %AuthPlayer{id: viewer_id}},
        game_id,
        %GameSummary{} = summary,
        category_names,
        available_words \\ nil
      )
      when is_list(category_names) do
    word_options = WordOptions.normalize(summary.word_options)
    player_count = map_size(summary.players)
    players = players_from_map(summary.players)
    owner_id = summary.owner && summary.owner.id
    is_owner? = not is_nil(owner_id) and owner_id == viewer_id
    participant? = participant_in_entries?(players, viewer_id)

    %__MODULE__{
      id: game_id,
      name: summary.name,
      status: summary.game_status,
      max_players: summary.max_players,
      player_count: player_count,
      empty_seats: max(summary.max_players - player_count, 0),
      language: word_options.language,
      category_names: category_names,
      owner_id: owner_id,
      owner_username: (summary.owner && summary.owner.username) || "",
      players: players,
      is_owner?: is_owner?,
      participant?: participant?,
      can_edit_settings?: summary.game_status == :lobby and is_owner?,
      can_leave?: summary.game_status == :lobby and participant?,
      can_transfer_ownership?: summary.game_status == :lobby and is_owner?,
      word_availability:
        build_word_availability(
          summary.game_status,
          available_words,
          player_count,
          summary.max_players,
          word_options.language,
          word_options.category_ids != []
        )
    }
  end

  defp participant_in_entries?(players, viewer_id) do
    Enum.any?(players, &(&1.id == viewer_id))
  end

  defp build_word_availability(
         :lobby,
         available_words,
         player_count,
         max_players,
         language,
         has_category_filter?
       )
       when is_integer(available_words) do
    WordAvailability.evaluate(%{
      available_words: available_words,
      player_count: player_count,
      max_players: max_players,
      language: language,
      has_category_filter?: has_category_filter?
    })
  end

  defp build_word_availability(_status, _available, _players, _max, _lang, _filter), do: nil

  defp players_from_map(players_map) when is_map(players_map) do
    players_map
    |> Enum.sort_by(fn {pos, _gp} -> pos end)
    |> Enum.map(fn {_pos, gp} ->
      %{id: gp.player.id, username: gp.player.username}
    end)
  end
end
