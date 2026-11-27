defmodule Forka.Repo.Migrations.AddOwnerlessVisibleGamesIndex do
  use Ecto.Migration

  def change do
    create index(:games, ["inserted_at DESC", "id DESC"],
             where: "owner_id IS NULL AND status <> 'archived'",
             name: :games_ownerless_visible_order_idx
           )
  end
end
