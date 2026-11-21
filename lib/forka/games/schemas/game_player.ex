defmodule Forka.Games.Schemas.GamePlayer do
  @moduledoc """
  This module represents a player within a specific game session.

  Each game player has:
  - A player struct containing the base player information (required)
  - A status indicating if the player is alive or dead (defaults to :alive)
  - Lives remaining in the game (defaults to 6)
  - A connection status indicating if connected/disconnected (defaults to :disconnected)
  - A score that tracks points earned in the current game (defaults to 0)

  The GamePlayer wraps the base Player struct with game-specific attributes like lives, status, and score,
  allowing the same player to participate in multiple games with different states.
  """

  use Ecto.Schema

  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.Player

  import Ecto.Changeset

  # Player in hangman starts with 6 lives
  @initial_lives 6

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "game_players" do
    belongs_to :game, Game
    belongs_to :player, Player
    field :status, Ecto.Enum, values: [:alive, :dead], default: :alive
    field :lives, :integer, default: @initial_lives
    field :score, :integer, default: 0
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          game_id: Ecto.UUID.t() | nil,
          game: Game.t() | Ecto.Association.NotLoaded.t(),
          player_id: Ecto.UUID.t() | nil,
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          status: :alive | :dead | nil,
          lives: integer() | nil,
          score: integer() | nil,
          position: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc "Casts attributes for a player participating in a game."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(game_player, attrs) do
    game_player
    |> cast(attrs, [:player_id, :status, :lives, :score])
    |> validate_required([:player_id])
    |> foreign_key_constraint(:player_id)
  end

  @doc false
  @spec new(Player.t()) :: t()
  def new(%Player{} = player), do: %__MODULE__{player: player, player_id: player.id}

  @doc false
  @spec decrement_lives(t()) :: t()
  def decrement_lives(%__MODULE__{status: :alive, lives: lives} = game_player) when lives > 1,
    do: %{game_player | lives: lives - 1}

  @doc false
  def decrement_lives(%__MODULE__{status: :alive, lives: lives} = game_player)
      when lives in [0, 1],
      do: %{game_player | lives: 0, status: :dead}

  @doc false
  def decrement_lives(%__MODULE__{} = game_player), do: game_player

  @doc false
  @spec reset_lives(t()) :: t()
  def reset_lives(%__MODULE__{} = game_player),
    do: %{game_player | lives: @initial_lives, status: :alive}

  @doc false
  @spec give_up(t()) :: t()
  def give_up(%__MODULE__{} = game_player),
    do: %{game_player | status: :dead, lives: 0}

  @doc false
  @spec add_score(t(), integer()) :: t()
  def add_score(%__MODULE__{status: :alive, score: score} = game_player, points)
      when is_integer(points) do
    %{game_player | score: score + points}
  end

  def add_score(%__MODULE__{} = game_player, points) when is_integer(points), do: game_player

  @doc false
  @spec died?(t()) :: boolean()
  def died?(%__MODULE__{status: :dead}), do: true
  def died?(%__MODULE__{}), do: false

  @doc false
  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{status: :alive}), do: true
  def alive?(%__MODULE__{}), do: false
end
