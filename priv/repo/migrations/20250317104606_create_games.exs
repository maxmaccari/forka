defmodule Forka.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "lobby"
      add :owner_id, references(:players, type: :binary_id, on_delete: :nilify_all)
      add :max_players, :integer, null: false, default: 2
      add :word_options, :map, default: %{}
      add :current_game_word_index, :integer
      add :current_game_player_index, :integer
      add :tick, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:games, [:owner_id])
    create index(:games, [:status])
  end
end
