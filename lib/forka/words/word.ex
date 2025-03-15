defmodule Forka.Words.Word do
  use Ecto.Schema
  import Ecto.Changeset

  alias Forka.Words.Category

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "words" do
    field :text, :string

    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(word, attrs) do
    word
    |> cast(attrs, [:text, :category_id])
    |> validate_required([:text, :category_id])
  end
end
