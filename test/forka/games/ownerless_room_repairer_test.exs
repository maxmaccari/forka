defmodule Forka.Games.OwnerlessRoomRepairerTest do
  use Forka.DataCase

  import Ecto.Query, only: [from: 2]

  alias Forka.Games
  alias Forka.Games.Core
  alias Forka.Games.OwnerlessRoomRepairer
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Game

  test "F-09: drains populated ownerless rooms across resumed batches before archiving empty ones" do
    repairer =
      start_supervised!(
        {OwnerlessRoomRepairer,
         name: :"repairer_#{System.unique_integer([:positive])}", batch_size: 2}
      )

    base = ~U[2026-11-27 16:00:00Z]

    set_inserted_at = fn game_id, offset_seconds ->
      ts = DateTime.add(base, offset_seconds, :second)

      from(g in Game, where: g.id == ^game_id)
      |> Repo.update_all(set: [inserted_at: ts])
    end

    member = insert(:player, username: "bruno")

    insert_orphan = fn name, offset_seconds, populated? ->
      owner = insert(:player)
      {:ok, game} = Repository.insert_game(owner.id, %{name: name, max_players: 4})

      if populated? do
        {:ok, state} = Repository.get_game_state(game.id)
        {:ok, state} = Core.join_game(state, Repository.get_player(member.id))
        {:ok, _} = Repository.save_game_state(state)
      end

      set_inserted_at.(game.id, offset_seconds)
      Repo.delete!(owner)
      game
    end

    # 3 newer empty orphans + 3 older populated orphans -> batch_size 2 forces cursor resumption
    # in :populated, transition to :empty, and multiple batches in :empty.
    empties =
      for i <- 1..3 do
        insert_orphan.("Vazia #{i}", 500 + i, false)
      end

    populated =
      for i <- 1..3 do
        insert_orphan.("Populada #{i}", 100 + i, true)
      end

    :ok = Games.subscribe_to_game_list()
    :ok = OwnerlessRoomRepairer.schedule_drain(repairer)
    :ok = OwnerlessRoomRepairer.await_idle(repairer)

    # All 3 populated rooms were promoted and broadcast as :repaired before empty ones archived
    repaired_ids =
      for _ <- 1..3 do
        assert_receive {:game_list_updated, %{id: id, action: :repaired, owner_username: "bruno"}}
        id
      end

    assert repaired_ids == populated |> Enum.reverse() |> Enum.map(& &1.id)

    for game <- populated do
      assert {:ok, %{status: :lobby, owner: %{id: owner_id}}} = Repository.get_game_state(game.id)
      assert owner_id == member.id
    end

    for game <- empties do
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(game.id)
    end
  end
end
