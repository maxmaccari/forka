defmodule Forka.Words.Word do
  @moduledoc "An entry in the game dictionary with a category and an optional hint."

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

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          text: String.t() | nil,
          hint: String.t() | nil,
          category_id: Ecto.UUID.t() | nil,
          category: Category.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  @spec changeset(t(), map(), keyword()) :: Ecto.Changeset.t(t())
  def changeset(word, attrs, _metadata \\ []) do
    word
    |> word_changeset(attrs)
    |> assoc_constraint(:category)
  end

  @doc false
  @spec admin_changeset(t(), map(), keyword()) :: Ecto.Changeset.t(t())
  def admin_changeset(word, attrs, _metadata) do
    word
    |> word_changeset(attrs)
    |> validate_required([:category_id])
    |> foreign_key_constraint(:category_id)
  end

  defp word_changeset(word, attrs) do
    word
    |> cast(attrs, [:text, :hint, :category_id])
    |> validate_required([:text])
    |> unique_constraint([:text, :category_id])
    |> update_change(:text, &String.downcase/1)
  end
end
