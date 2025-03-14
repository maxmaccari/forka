defmodule Forka.Games.Player do
  @moduledoc """
  This module represents a player in the Forka game.

  Each Player has:
  - A unique ID (automatically generated)
  - A username (required)

  The Player struct is used to identify and track players throughout the game.
  Players can join games, make guesses, and interact with the game system.
  """

  defstruct id: nil, username: nil

  @doc false
  def new(username) when is_binary(username) do
    %__MODULE__{
      id: UUID.uuid4(),
      username: username
    }
  end
end
