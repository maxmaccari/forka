defmodule Forka.Words.Word do
  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Words.Category

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "words" do
    field :text, :string
    field :hint, :string

    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(word, attrs, _metadata \\ []) do
    word
    |> cast(attrs, [:text, :hint, :category_id])
    |> validate_required([:text, :category_id])
    |> unique_constraint([:text, :category_id])
  end
end
