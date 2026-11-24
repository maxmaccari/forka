defmodule Forka.Games.RoomListItem do
  @moduledoc """
  Read model for a room displayed in the public live room directory.

  Contains only non-sensitive summary fields safe to display to any visitor.
  """

  alias Forka.Games.Core.GameState
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.WordOptions

  @visible_statuses [:lobby, :playing, :finished, :game_over]

  @type availability :: :open | :full | :playing | :ended

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          status: GameState.status(),
          player_count: non_neg_integer(),
          max_players: pos_integer(),
          owner_username: String.t() | nil,
          language: String.t(),
          category_names: [String.t()]
        }

  defstruct id: nil,
            name: "",
            status: :lobby,
            player_count: 0,
            max_players: 2,
            owner_username: nil,
            language: "en",
            category_names: []

  @doc "Returns the statuses visible in the live room directory."
  @spec visible_statuses() :: [GameState.status()]
  def visible_statuses, do: @visible_statuses

  @doc "Returns true when a room with the given status should appear in the room directory."
  @spec visible_status?(GameState.status()) :: boolean()
  def visible_status?(status), do: status in @visible_statuses

  @doc "Returns true when a room is in the lobby and still has at least one open seat."
  @spec joinable?(t()) :: boolean()
  def joinable?(%__MODULE__{status: :lobby, player_count: count, max_players: max}),
    do: count < max

  def joinable?(%__MODULE__{}), do: false

  @doc "Classifies room availability for directory presentation."
  @spec availability_state(t()) :: availability()
  def availability_state(%__MODULE__{status: :lobby, player_count: count, max_players: max})
      when count < max,
      do: :open

  def availability_state(%__MODULE__{status: :lobby}), do: :full
  def availability_state(%__MODULE__{status: :playing}), do: :playing
  def availability_state(%__MODULE__{}), do: :ended

  @doc "Builds a RoomListItem from a persisted Game schema, player count, owner username, and category lookup map."
  @spec from_game(Game.t(), non_neg_integer(), String.t() | nil, %{Ecto.UUID.t() => String.t()}) ::
          t()
  def from_game(%Game{} = game, player_count, owner_username, categories_by_id)
      when is_integer(player_count) and player_count >= 0 and is_map(categories_by_id) do
    {language, category_ids} = extract_word_options(game.word_options)

    category_names =
      category_ids
      |> Enum.map(&Map.get(categories_by_id, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    %__MODULE__{
      id: game.id,
      name: game.name || "",
      status: game.status,
      player_count: player_count,
      max_players: game.max_players,
      owner_username: owner_username,
      language: language,
      category_names: category_names
    }
  end

  @doc "Builds a RoomListItem from a `:game_list_updated` broadcast payload."
  @spec from_event(map()) :: t()
  def from_event(%{id: id, name: name, status: status} = payload) do
    owner_username =
      Map.get(payload, :owner_username) ||
        case Map.get(payload, :owner) do
          %{username: username} when is_binary(username) -> username
          _ -> nil
        end

    %__MODULE__{
      id: id,
      name: name || "",
      status: status,
      player_count: Map.get(payload, :player_count, 0),
      max_players: Map.get(payload, :max_players, 2),
      owner_username: owner_username,
      language: Map.get(payload, :language) || "en",
      category_names: Map.get(payload, :category_names, [])
    }
  end

  defp extract_word_options(%WordOptions{language: lang, category_ids: ids}) do
    {lang || "en", ids || []}
  end

  defp extract_word_options(nil), do: {"en", []}
end
