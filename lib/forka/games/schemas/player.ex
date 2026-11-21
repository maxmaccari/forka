defmodule Forka.Games.Schemas.Player do
  @moduledoc """
  This module represents a player in the Forka game.

  Each Player has:
  - A unique ID (automatically generated)
  - A username (required)

  The Player struct is used to identify and track players throughout the game.
  Players can join games, make guesses, and interact with the game system.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "players" do
    field :username, :string

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          username: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  @spec to_map(t()) :: %{id: Ecto.UUID.t() | nil, username: String.t() | nil}
  def to_map(player) do
    %{
      id: player.id,
      username: player.username
    }
  end
end
