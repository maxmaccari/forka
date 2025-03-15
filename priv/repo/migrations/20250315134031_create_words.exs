defmodule Forka.Repo.Migrations.CreateWords do
  use Ecto.Migration

  def change do
    create table(:words, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :text, :citext, null: false
      add :hint, :string

      add :category_id, references(:categories, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:words, [:category_id])
    create unique_index(:words, [:text, :category_id])
  end
end
