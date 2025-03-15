defmodule Forka.Words.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "categories" do
    field :name, :string
    field :language, :string, default: "en"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :language])
    |> validate_required([:name])
    |> unique_constraint([:name, :language], name: :categories_lower_name_language_index)
    |> validate_length(:name, min: 2, message: "must have at least 2 characters")
    |> validate_format(:language, ~r/^[a-z]{2}(-[A-Z]{2})?$/,
      message:
        "must be a valid ISO language code (two lowercase letters, optionally followed by a hyphen and two uppercase letters for region)"
    )
  end
end
