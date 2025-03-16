defmodule Forka.Games.Player do
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
end
