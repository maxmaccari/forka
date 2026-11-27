defmodule ForkaWeb.Admin.PlayerLiveTest do
  use ForkaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Backpex.Testing
  alias Forka.Games
  alias Forka.Games.Core
  alias Forka.Games.GameServer
  alias Forka.Games.Repository
  alias Forka.Players.Player
  alias Forka.Repo
  alias Forka.Scope
  alias ForkaWeb.Admin.PlayerLive
  alias ForkaWeb.Router

  setup :register_and_log_in_admin

  describe "deleting players via PlayerLive" do
    test "hands off ownership to the next seat and updates live RoomLive and RoomDirectoryLive clients",
         %{conn: admin_conn} do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Sala Viva", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)

      on_exit(fn ->
        if pid = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      # Mount live player views before the admin deletes the owner
      {:ok, room_lv, _html} = build_conn() |> log_in_player(p2) |> live(~p"/rooms/#{game.id}")
      {:ok, dir_lv, _html} = live(build_conn(), ~p"/")
      _ = render_async(dir_lv)

      assert has_element?(dir_lv, "#rooms-#{game.id}", "lia")
      refute has_element?(room_lv, "#edit-room-settings")

      # Admin deletes owner via Backpex PlayerLive
      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))

      admin_lv
      |> Testing.click_item_action(:delete, owner)
      |> Testing.confirm_item_action()

      refute Repo.get(Player, owner.id)
      assert Games.get_game_summary(game.id).owner.id == p2.id

      # Live room client immediately receives ownership and edit controls
      _ = :sys.get_state(room_lv.pid)
      assert has_element?(room_lv, "#edit-room-settings")
      assert render(room_lv) =~ "Agora você comanda a sala."

      # Live directory immediately updates owner username and player count
      _ = :sys.get_state(dir_lv.pid)
      assert has_element?(dir_lv, "#rooms-#{game.id}", "bruno")
    end

    test "archives sole-owner room, stops its GameServer, and removes it from live RoomDirectoryLive",
         %{conn: admin_conn} do
      owner = insert(:player, username: "lia")
      {:ok, game} = Games.create_room(Scope.for_player(owner), %{name: "Solo", max_players: 4})

      pid = GameServer.whereis(game.id)
      ref = Process.monitor(pid)

      {:ok, dir_lv, _html} = live(build_conn(), ~p"/")
      _ = render_async(dir_lv)
      assert has_element?(dir_lv, "#rooms-#{game.id}")

      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))

      admin_lv
      |> Testing.click_item_action(:delete, owner)
      |> Testing.confirm_item_action()

      refute Repo.get(Player, owner.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(game.id)

      _ = :sys.get_state(dir_lv.pid)
      refute has_element?(dir_lv, "#rooms-#{game.id}")
    end

    test "handles a player across several rooms including cold, playing, non-owner, and archived rooms",
         %{conn: admin_conn} do
      target = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")
      insert_list(6, :word)

      # Cold sole-owner lobby room (no running server)
      {:ok, cold_solo} = Repository.insert_game(target.id, %{name: "Fria Solo", max_players: 4})
      assert GameServer.whereis(cold_solo.id) == nil

      # Cold shared lobby room (no running server)
      {:ok, cold_shared} =
        Repository.insert_game(target.id, %{name: "Fria Compartilhada", max_players: 4})

      {:ok, cs} = Repository.get_game_state(cold_shared.id)
      {:ok, cs} = Core.join_game(cs, Repository.get_player(p2.id))
      {:ok, _} = Repository.save_game_state(cs)
      assert GameServer.whereis(cold_shared.id) == nil

      # Running playing match
      {:ok, playing} =
        Games.create_room(Scope.for_player(target), %{name: "Em Jogo", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), playing.id)
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p3), playing.id)
      assert :ok = Games.start_game(Scope.for_player(target), playing.id)

      # Archived room
      {:ok, archived_room} =
        Repository.insert_game(target.id, %{name: "Arquivada", max_players: 4})

      {:ok, as} = Repository.get_game_state(archived_room.id)
      {:ok, archived} = Core.archive_game(as)
      {:ok, _} = Repository.save_game_state(archived)

      on_exit(fn ->
        for id <- [cold_shared.id, playing.id] do
          if pid = GameServer.whereis(id) do
            DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
          end
        end
      end)

      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))

      admin_lv
      |> Testing.click_item_action(:delete, target)
      |> Testing.confirm_item_action()

      refute Repo.get(Player, target.id)
      assert GameServer.whereis(cold_solo.id) == nil
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(cold_solo.id)

      assert Games.get_game_summary(cold_shared.id).owner.id == p2.id

      playing_summary = Games.get_game_summary(playing.id)
      assert playing_summary.game_status == :playing
      assert playing_summary.owner.id in [p2.id, p3.id]
      refute Enum.any?(playing_summary.players, fn {_, gp} -> gp.player.id == target.id end)

      assert GameServer.whereis(archived_room.id) == nil
      assert {:ok, %{status: :archived, owner: nil}} = Repository.get_game_state(archived_room.id)
    end

    test "batch deleting several players archives a room when all its players are deleted and hands off when one remains",
         %{conn: admin_conn} do
      p1 = insert(:player, username: "ana")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")

      # Room with only p1 and p2 (both will be deleted in one batch -> archived)
      {:ok, both_deleted_room} =
        Games.create_room(Scope.for_player(p1), %{name: "Todos Fora", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), both_deleted_room.id)
      both_pid = GameServer.whereis(both_deleted_room.id)
      both_ref = Process.monitor(both_pid)

      # Room with p1, p2, and p3 (p1 and p2 deleted in batch -> p3 takes over)
      {:ok, survivor_room} =
        Games.create_room(Scope.for_player(p1), %{name: "Sobra Caio", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), survivor_room.id)
      assert {:ok, :joined} = Games.join_room(Scope.for_player(p3), survivor_room.id)

      on_exit(fn ->
        if pid = GameServer.whereis(survivor_room.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))

      admin_lv
      |> Testing.select_item(p1)
      |> Testing.select_item(p2)
      |> Testing.click_item_action(:delete)
      |> Testing.confirm_item_action()

      refute Repo.get(Player, p1.id)
      refute Repo.get(Player, p2.id)
      assert Repo.get(Player, p3.id)

      assert_receive {:DOWN, ^both_ref, :process, ^both_pid, :normal}

      assert {:ok, %{status: :archived, owner: nil, game_players: %{}}} =
               Repository.get_game_state(both_deleted_room.id)

      survivor_summary = Games.get_game_summary(survivor_room.id)
      assert survivor_summary.game_status == :lobby
      assert survivor_summary.owner.id == p3.id
      assert Map.keys(survivor_summary.players) == [0]
      assert survivor_summary.players[0].player.id == p3.id
    end

    test "refuses deletion with an error message instead of crashing when removing from a room fails",
         %{conn: admin_conn} do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Conflito", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)

      pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)

      on_exit(fn ->
        _ = :sys.get_state(Process.whereis(Forka.GamesSupervisor))

        if restarted = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, restarted)
        end
      end)

      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))
      Testing.click_item_action(admin_lv, :delete, owner)

      :ok = :sys.suspend(pid)

      confirm_task =
        try do
          :erlang.trace(pid, true, [:receive])

          task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Testing.confirm_item_action(admin_lv)
            end)

          assert_receive {:trace, ^pid, :receive, {:"$gen_call", _, {:remove_player, _}}}, 2_000
          Process.exit(pid, :kill)
          task
        after
          :erlang.trace(:all, false, [:receive])
        end

      Task.await(confirm_task, 5_000)

      {path, flash} = assert_redirect(admin_lv)
      assert flash["error"] =~ "Could not remove player from active rooms"
      assert Repo.get(Player, owner.id)

      {:ok, refreshed_lv, _html} = live(admin_conn, path)
      assert has_element?(refreshed_lv, "#row-item-#{owner.id}")
    end

    test "refuses the whole batch deletion when removing one player fails", %{conn: admin_conn} do
      p1 = insert(:player, username: "ana")
      p2 = insert(:player, username: "bruno")
      p3 = insert(:player, username: "caio")

      {:ok, healthy_room} =
        Games.create_room(Scope.for_player(p1), %{name: "Sala Normal", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p3), healthy_room.id)

      {:ok, broken_room} =
        Games.create_room(Scope.for_player(p2), %{name: "Sala Conflito", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p3), broken_room.id)

      broken_pid = GameServer.whereis(broken_room.id)
      task_supervisor = start_supervised!(Task.Supervisor)

      on_exit(fn ->
        _ = :sys.get_state(Process.whereis(Forka.GamesSupervisor))

        for id <- [healthy_room.id, broken_room.id] do
          if pid = GameServer.whereis(id) do
            DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
          end
        end
      end)

      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))

      admin_lv
      |> Testing.select_item(p1)
      |> Testing.select_item(p2)
      |> Testing.click_item_action(:delete)

      :ok = :sys.suspend(broken_pid)

      confirm_task =
        try do
          :erlang.trace(broken_pid, true, [:receive])

          task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Testing.confirm_item_action(admin_lv)
            end)

          assert_receive {:trace, ^broken_pid, :receive, {:"$gen_call", _, {:remove_player, _}}},
                         2_000

          Process.exit(broken_pid, :kill)
          task
        after
          :erlang.trace(:all, false, [:receive])
        end

      Task.await(confirm_task, 5_000)

      {_path, flash} = assert_redirect(admin_lv)
      assert flash["error"] =~ "Could not remove player from active rooms"
      assert Repo.get(Player, p1.id)
      assert Repo.get(Player, p2.id)
    end

    test "on_item_deleting/2 refuses unauthorized calls without an authenticated admin" do
      owner = insert(:player, username: "lia")
      p2 = insert(:player, username: "bruno")

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Protegida", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)

      on_exit(fn ->
        if pid = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, pid)
        end
      end)

      assert {:error, message} = PlayerLive.on_item_deleting(%{assigns: %{}}, owner)
      assert is_binary(message)
      assert Games.get_game_summary(game.id).owner.id == owner.id
    end

    test "F-14: waits past 5s when a room is busy instead of cancelling and leaving a queued removal behind",
         %{conn: admin_conn} do
      owner = insert(:player, username: "f14_lia")
      p2 = insert(:player, username: "f14_bruno")
      owner_id = owner.id

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Sala Ocupada", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)

      on_exit(fn ->
        if running = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, running)
        end
      end)

      {:ok, admin_lv, _html} = live(admin_conn, Testing.path(Router, PlayerLive, :index))
      Testing.click_item_action(admin_lv, :delete, owner)

      :ok = :sys.suspend(pid)

      confirm_task =
        try do
          :erlang.trace(pid, true, [:receive])

          task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              Testing.confirm_item_action(admin_lv)
            end)

          assert_receive {:trace, ^pid, :receive, {:"$gen_call", _, {:remove_player, ^owner_id}}},
                         2_000

          # Hold past the default 5_000ms GenServer.call timeout
          Process.send_after(self(), :resume_busy_room, 5_200)
          assert_receive :resume_busy_room, 6_000

          # No premature timeout cancellation; both account and room remain unchanged while blocked
          assert Task.yield(task, 0) == nil
          assert Repo.get(Player, owner.id) != nil
          assert {:ok, %{owner: %{id: ^owner_id}}} = Repository.get_game_state(game.id)

          :ok = :sys.resume(pid)
          task
        after
          :erlang.trace(:all, false, [:receive])

          try do
            :sys.resume(pid)
          catch
            :exit, _ -> :ok
          end
        end

      Task.await(confirm_task, 5_000)

      refute Repo.get(Player, owner.id)
      assert Games.get_game_summary(game.id).owner.id == p2.id
      assert {:ok, %{owner: %{id: p2_id}}} = Repository.get_game_state(game.id)
      assert p2_id == p2.id
    end

    test "F-14: distinguishes uncertain removal outcome from an explicit refusal in on_item_deleting/2",
         %{admin: admin} do
      owner = insert(:player, username: "f14_unc_lia")
      p2 = insert(:player, username: "f14_unc_bruno")
      owner_id = owner.id

      {:ok, game} =
        Games.create_room(Scope.for_player(owner), %{name: "Sala Incerta", max_players: 4})

      assert {:ok, :joined} = Games.join_room(Scope.for_player(p2), game.id)
      pid = GameServer.whereis(game.id)
      task_supervisor = start_supervised!(Task.Supervisor)

      on_exit(fn ->
        _ = :sys.get_state(Process.whereis(Forka.GamesSupervisor))

        if restarted = GameServer.whereis(game.id) do
          DynamicSupervisor.terminate_child(Forka.GamesSupervisor, restarted)
        end
      end)

      :ok = :sys.suspend(pid)

      hook_task =
        try do
          :erlang.trace(pid, true, [:receive])

          task =
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              PlayerLive.on_item_deleting(%{assigns: %{current_admin: admin}}, owner)
            end)

          assert_receive {:trace, ^pid, :receive, {:"$gen_call", _, {:remove_player, ^owner_id}}},
                         2_000

          Process.exit(pid, :noconnection)
          task
        after
          :erlang.trace(:all, false, [:receive])
        end

      assert {:error, message} = Task.await(hook_task, 5_000)
      assert message =~ "Could not confirm"
      assert Repo.get(Player, owner.id) != nil
      assert {:ok, %{owner: %{id: ^owner_id}}} = Repository.get_game_state(game.id)
    end
  end
end
