defmodule Forka.Repo.Migrations.CreateGameWords do
  use Ecto.Migration

  def change do
    create table(:game_words, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      # Embedded schema for Word
      add :word, :map, null: false
      # Embedded schema for Guess
      add :guesses, {:array, :map}, default: []
      add :finished_by_id, references(:players, type: :binary_id, on_delete: :nilify_all)
      add :base_word_id, references(:words, type: :binary_id, on_delete: :nilify_all)
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:game_words, [:game_id])
    create index(:game_words, [:base_word_id])
    create index(:game_words, [:game_id, :position])
  end
end
