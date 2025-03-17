defmodule Forka.Games.Schemas.Game do
  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Games.Schemas.GameWord
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.WordOptions
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Game.GameState

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

    has_many :game_words, GameWord,
      foreign_key: :game_id,
      preload_order: [asc: :position],
      on_replace: :delete

    has_many :game_players, GamePlayer,
      foreign_key: :game_id,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  # Changeset
  # TODO: Make three changesets: insert_changeset and update_changeset.
  # insert_changeset will make it able only to set the name, status, and max_players
  # update_changeset will make it able to set other fields, but according to state
  # lobby state will allow to change settings and owner
  # archived state won't allow to change nothing
  # playing state will allow to change anything else but settings (it will allow to change owner too)
  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :name,
      :status,
      :max_players,
      :current_game_word_index,
      :current_game_player_index,
      :owner_id
    ])
    |> validate_required([:name, :status, :max_players])
    |> validate_number(:max_players,
      greater_than_or_equal_to: 2,
      less_than_or_equal_to: 6,
      message: "must be between 2 and 6 players"
    )
    |> foreign_key_constraint(:owner_id)
    |> cast_embed(:word_options)
    |> cast_assoc(:game_words)
    |> cast_assoc(:game_players)
  end

  # Conversion functions
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
      game_words: map_to_list_with_position(game_state.words),
      game_players: map_to_list_with_position(game_state.players)
    }
  end

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
      words: list_to_map(game.game_words),
      players: list_to_map(game.game_players)
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
end
