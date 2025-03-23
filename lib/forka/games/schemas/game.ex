defmodule Forka.Games.Schemas.Game do
  @moduledoc """
  Database schema for game records.

  This schema defines the database structure for persisting games in the Forka application.
  It handles the mapping between database records and Elixir structs, including:

  - Basic game information (name, max players)
  - Game configuration (word options)
  - Current game state (status, indices)
  - Relationships (players, words, events)

  Game records can have the following statuses:
  - `:lobby` - Initial state where players can join
  - `:playing` - Active gameplay
  - `:finished` - Game completed normally
  - `:game_over` - Game ended prematurely
  - `:archived` - Game no longer active

  This schema is used internally by the Games context and should not be used directly
  by other contexts. All game interactions should go through the Games context module.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Games.Core.GameState
  alias Forka.Games.Schemas.Event
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.WordOptions

  import Forka.Games.Core, only: [min_players_allowed: 0, max_players_allowed: 0]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "games" do
    field :name, :string
    field :max_players, :integer
    embeds_one :word_options, WordOptions, on_replace: :delete

    belongs_to :owner, Player

    field :status, Ecto.Enum,
      values: [:lobby, :playing, :finished, :archived, :game_over],
      default: :lobby

    field :current_game_word_index, :integer
    field :current_game_player_index, :integer
    field :tick, :integer, default: 0

    has_many :game_words, GameWord,
      foreign_key: :game_id,
      preload_order: [asc: :position],
      on_replace: :delete

    has_many :game_players, GamePlayer,
      foreign_key: :game_id,
      preload_order: [asc: :position],
      on_replace: :delete

    has_many :events, Event,
      foreign_key: :game_id,
      preload_order: [desc: :tick, desc: :at],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def insert_changeset(game, attrs) do
    game
    |> cast(attrs, [:name, :max_players, :owner_id, :tick])
    |> common_changeset()
  end

  def update_changeset(game, attrs) do
    game
    |> cast(attrs, [
      :name,
      :max_players,
      :owner_id,
      :status,
      :current_game_word_index,
      :current_game_player_index,
      :tick
    ])
    |> validate_required([:status])
    |> common_changeset()
    |> validate_status_update(game.status)
  end

  defp common_changeset(changeset) do
    changeset
    |> validate_required([:owner_id])
    |> validate_settings()
    |> foreign_key_constraint(:owner_id)
    |> cast_assoc(:events)
    |> cast_assoc(:game_words)
    |> cast_assoc(:game_players)
    |> cast_embed(:word_options)
    |> validate_number(:tick, greater_than_or_equal_to: 0)
  end

  defp validate_settings(changeset) do
    changeset
    |> validate_required([:name, :max_players])
    |> validate_number(:max_players,
      greater_than_or_equal_to: min_players_allowed(),
      less_than_or_equal_to: max_players_allowed(),
      message: "must be between #{min_players_allowed()} and #{max_players_allowed()} players"
    )
  end

  defp validate_status_update(changeset, current_status) do
    case current_status do
      :archived ->
        add_error(changeset, :status, "cannot update an archived game")

      _ ->
        changeset
    end
  end

  # Conversion functions
  @doc false
  def from_game_state(%GameState{} = game_state) do
    # Convert GameState to Game schema
    %__MODULE__{
      id: game_state.id,
      name: game_state.name,
      status: game_state.status,
      max_players: game_state.max_players,
      current_game_word_index: game_state.current_game_word_index,
      current_game_player_index: game_state.current_game_player_index,
      word_options: game_state.word_options,
      owner_id: game_state.owner && game_state.owner.id,
      game_words: map_to_list_with_position(game_state.game_words),
      game_players: map_to_list_with_position(game_state.game_players),
      events: game_state.events
    }
  end

  @doc false
  def to_game_state(%__MODULE__{} = game) do
    # Convert Game schema to GameState
    %GameState{
      id: game.id,
      name: game.name,
      status: game.status,
      max_players: game.max_players,
      current_game_word_index: game.current_game_word_index,
      current_game_player_index: game.current_game_player_index,
      word_options: game.word_options,
      owner: game.owner,
      game_words: list_to_map(game.game_words),
      game_players: list_to_map(game.game_players),
      events: game.events
    }
  end

  # Helper functions for conversion
  defp map_to_list_with_position(map) when is_map(map) do
    Enum.map(map, fn {index, item} -> %{item | position: index} end)
  end

  defp list_to_map(list) when is_list(list) do
    list
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index()
    |> Map.new(fn {v, k} -> {k, v} end)
  end

  @doc """
  Converts a Game schema struct to a plain map.

  This function removes Ecto metadata and virtual fields, and processes nested associations
  to ensure they are also converted to plain maps. It's useful for serialization or when
  preparing data for database operations.

  ## Parameters

    * `game` - The Game schema struct to convert

  ## Returns

  A map representation of the Game with all Ecto metadata and associations properly processed.
  """
  def to_map(%__MODULE__{} = game) do
    # Then convert the Game schema to a map, removing the __struct__ and other Ecto metadata
    game_params = Map.from_struct(game)

    # Clean up any virtual fields or associations that might cause issues
    game_params
    |> Map.drop([:__meta__, :owner, :inserted_at, :updated_at])
    |> Map.update(:game_words, [], fn game_words ->
      Enum.map(game_words, fn game_word ->
        game_word
        |> Map.from_struct()
        |> Map.update(:word, nil, &(&1 |> Map.from_struct() |> Map.drop([:__meta__])))
        |> Map.drop([:__meta__, :game, :game_id, :inserted_at, :updated_at])
        |> Map.update(:guesses, [], fn guesses ->
          Enum.map(guesses, &Map.from_struct/1)
        end)
      end)
    end)
    |> Map.update(:game_players, [], fn game_players ->
      Enum.map(game_players, fn game_player ->
        game_player
        |> Map.from_struct()
        |> Map.drop([:__meta__, :player, :game, :game_id, :inserted_at, :updated_at])
      end)
    end)
    |> Map.update(:word_options, nil, fn word_options ->
      if word_options do
        word_options
        |> Map.from_struct()
        |> Map.drop([:__meta__])
      else
        %{}
      end
    end)
    |> Map.update(:events, [], fn events ->
      Enum.map(events, &Event.to_map/1)
    end)
  end
end
