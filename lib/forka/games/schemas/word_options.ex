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

  @type t :: %__MODULE__{
          language: String.t() | nil,
          category_ids: [Ecto.UUID.t()] | nil
        }

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(word_options, attrs) do
    word_options
    |> cast(attrs, [:language, :category_ids])
    |> validate_required([:language])
  end

  @doc false
  @spec new(map()) :: t()
  def new(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_changes()
  end
end
