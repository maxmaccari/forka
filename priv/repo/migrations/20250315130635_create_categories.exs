defmodule Forka.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :language, :string, null: false, default: "en"

      timestamps(type: :utc_datetime)
    end
  end
end
