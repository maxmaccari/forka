defmodule Forka.Race do
  @moduledoc """
  Stages a race between two players or tabs that the sandbox cannot stage on
  its own: `after_query/3` runs `fun`, as the other actor, inside `pid` (a
  LiveView or test process) right after `pid`'s next Repo query that `match`
  accepts, so it lands between two reads or writes of one event.

  It runs once, then detaches. `fun` runs in `pid`, through the same sandbox
  connection. `match` must pick a query outside a transaction, or a
  transaction's `"rollback"` or `"commit"` entry: for a query inside a
  transaction, `fun` would join that transaction, which no real race can do.
  Queries inside a transaction are skipped and the handler stays attached. A
  `match` that raises counts as no match too. A handler still attached when
  the test ends never ran `fun`, so teardown fails the test: a race that was
  not staged proves nothing. The failure includes the first exception `match`
  raised, if any. If `fun` raises, throws, or exits, teardown fails the test
  with that failure too, instead of letting Telemetry swallow it.
  """

  @event [:forka, :repo, :query]

  @doc """
  Runs `fun` in `pid` after `pid`'s next query outside a transaction whose
  telemetry metadata `match` accepts (`&(&1.source == "games")`,
  `&(&1.query == "rollback")`). Fails the test at teardown if no query matched
  or if `fun` failed.
  """
  @spec after_query(pid(), (map() -> boolean()), (-> any())) :: :ok
  def after_query(pid, match, fun) do
    ExUnit.Callbacks.on_exit(arm(pid, match, fun))
  end

  @doc false
  @spec arm(pid(), (map() -> boolean()), (-> any())) :: (-> :ok)
  def arm(pid, match, fun) do
    id = {__MODULE__, make_ref()}
    # Holds handler completion state and the first exception `match` raises.
    # Unlinked, since `on_exit` runs after the test process exits; teardown stops it.
    {:ok, state} = Agent.start(fn -> %{status: :pending, match_error: nil} end)
    config = %{id: id, pid: pid, match: match, fun: fun, state: state}
    :ok = :telemetry.attach(id, @event, &__MODULE__.handle_query/4, config)

    fn ->
      _ = :telemetry.detach(id)
      final_state = Agent.get(state, & &1)
      :ok = Agent.stop(state)

      case final_state do
        %{status: :completed} ->
          :ok

        %{status: {:failed, error}} ->
          ExUnit.Assertions.flunk(callback_failed_message(error))

        %{status: :running} ->
          ExUnit.Assertions.flunk("Race.after_query/3: callback did not complete")

        %{status: :pending, match_error: error} ->
          ExUnit.Assertions.flunk(no_match_message(error))
      end
    end
  end

  @doc false
  def handle_query(_event, _measurements, metadata, %{id: id, pid: pid, state: state} = config) do
    if self() == pid and not Forka.Repo.in_transaction?() and matches?(config, metadata) do
      :telemetry.detach(id)
      Agent.update(state, &%{&1 | status: :running})
      run_callback(config)
    end

    :ok
  end

  # `:telemetry` detaches a handler that raises and only logs it, so teardown
  # would see it gone and pass. A raising `match` is no match; teardown
  # reports its first exception.
  defp matches?(%{match: match, state: state}, metadata) do
    match.(metadata)
  catch
    kind, reason ->
      formatted = Exception.format(kind, reason, __STACKTRACE__)

      Agent.update(state, fn
        %{match_error: nil} = current -> %{current | match_error: formatted}
        current -> current
      end)

      false
  end

  defp run_callback(%{fun: fun, state: state}) do
    fun.()
    Agent.update(state, &%{&1 | status: :completed})
  catch
    kind, reason ->
      formatted = Exception.format(kind, reason, __STACKTRACE__)
      Agent.update(state, &%{&1 | status: {:failed, formatted}})
  end

  defp no_match_message(nil),
    do: "Race.after_query/3: no matching query outside a transaction"

  defp no_match_message(error),
    do: no_match_message(nil) <> "\n\n`match` raised:\n\n" <> error

  defp callback_failed_message(error),
    do: "Race.after_query/3: callback failed:\n\n" <> error
end
