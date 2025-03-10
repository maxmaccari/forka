defmodule Forka.Games.Game.Guess do
  @moduledoc """
  This module represents a guess made by a player in the Forka game.

  Each guess has:
  - A letter that was guessed (required)
  - The ID of the player who made the guess (required)
  - A timestamp of when the guess was made
  - A boolean indicating if the guess was correct
  """

  defstruct letter: nil, guessed_by_player_id: nil, guessed_at: nil, correct?: false

  @doc false
  def new(letter, guessed_by_player_id, correct?) do
    %__MODULE__{
      letter: String.downcase(letter),
      guessed_by_player_id: guessed_by_player_id,
      correct?: correct?,
      guessed_at: DateTime.utc_now()
    }
  end
end

defimpl Inspect, for: Forka.Games.Game.Guess do
  import Inspect.Algebra

  def inspect(%Forka.Games.Game.Guess{letter: letter, correct?: correct?}, _opts) do
    status = if correct?, do: "✓", else: "✗"
    concat(["#Guess<\"", letter, "\" ", status, ">"])
  end
end
