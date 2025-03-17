defmodule Forka.Repo.Migrations.CreateGamePlayers do
  use Ecto.Migration

  def change do
    create table(:game_players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "alive"
      add :lives, :integer, null: false, default: 6
      add :score, :integer, null: false, default: 0
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:game_players, [:game_id])
    create index(:game_players, [:player_id])
    create unique_index(:game_players, [:game_id, :player_id])
    create index(:game_players, [:game_id, :position])
  end
end
