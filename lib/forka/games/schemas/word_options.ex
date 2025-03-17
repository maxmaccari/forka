defmodule Forka.Games.Schemas.WordOptions do
  @moduledoc """
  Embedded schema for word options used in game filtering.

  This schema represents options for filtering words in a game, including:
  - language: The language of the words to be used in the game
  - category_ids: Optional list of category IDs to filter words by
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :language, :string, default: "en"
    field :category_ids, {:array, :binary_id}, default: []
  end

  @doc false
  def changeset(word_options, attrs) do
    word_options
    |> cast(attrs, [:language, :category_ids])
    |> validate_required([:language])
  end

  @doc false
  def new(attrs \\ []) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_changes()
  end
end
