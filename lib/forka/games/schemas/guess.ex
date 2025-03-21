defmodule Forka.Games.Schemas.Guess do
  @moduledoc """
  This module represents a guess made by a player in the Forka game.

  Each guess has:
  - A letter that was guessed (required)
  - The ID of the player who made the guess (required)
  - A timestamp of when the guess was made
  - A boolean indicating if the guess was correct
  """

  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :letter, :string
    field :guessed_by_player_id, :string
    field :guessed_at, :utc_datetime
    field :correct?, :boolean, default: false
  end

  @doc false
  def changeset(guess, attrs) do
    # Used internally by Ecto when persisting through cast_embedded
    # This function won't be called directly in application code
    guess
    |> cast(attrs, [:letter, :guessed_by_player_id, :guessed_at, :correct?])
    |> validate_required([:letter, :guessed_by_player_id])
  end

  @doc false
  def new(letter, guessed_by_player_id, correct?) do
    %__MODULE__{
      letter: String.downcase(letter),
      guessed_by_player_id: guessed_by_player_id,
      correct?: correct?,
      guessed_at: DateTime.utc_now()
    }
  end

  @doc false
  def to_map(%__MODULE__{} = guess) do
    %{
      letter: guess.letter,
      guessed_by_player_id: guess.guessed_by_player_id,
      guessed_at: guess.guessed_at,
      correct: guess.correct?
    }
  end
end
