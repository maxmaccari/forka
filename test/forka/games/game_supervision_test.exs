defmodule Forka.Games.GameSupervisionTest do
  use Forka.DataCase

  alias Forka.Games.GameServer
  alias Forka.Games.Repository

  @tag audit_f01: true
  @tag :capture_log
  test "F-01 archiving a supervised game leaves its sibling running" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    archived = insert(:game)
    sibling = insert(:game)
    {:ok, archived_pid} = DynamicSupervisor.start_child(supervisor, {GameServer, archived.id})
    {:ok, sibling_pid} = DynamicSupervisor.start_child(supervisor, {GameServer, sibling.id})
    archived_ref = Process.monitor(archived_pid)
    sibling_ref = Process.monitor(sibling_pid)

    assert :ok = GameServer.archive_game(archived.id)
    assert_receive {:DOWN, ^archived_ref, :process, ^archived_pid, :normal}
    refute_receive {:DOWN, ^sibling_ref, :process, ^sibling_pid, _reason}, 1_000

    assert Process.alive?(supervisor)
    assert GameServer.whereis(sibling.id) == sibling_pid
    assert %{game_status: :lobby} = GameServer.get_game(sibling.id)
    assert {:ok, %{status: :archived}} = Repository.get_game_state(archived.id)
  end
end
