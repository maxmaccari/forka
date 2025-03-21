defmodule Forka.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :at, :utc_datetime, null: false
      add :payload, :map

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:game_id])
    create index(:events, [:game_id, :tick])
  end
end
