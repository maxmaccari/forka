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
  raised, if any.
  """

  @event [:forka, :repo, :query]

  @doc """
  Runs `fun` in `pid` after `pid`'s next query outside a transaction whose
  telemetry metadata `match` accepts (`&(&1.source == "games")`,
  `&(&1.query == "rollback")`). Fails the test at teardown if no query matched.
  """
  @spec after_query(pid(), (map() -> boolean()), (-> any())) :: :ok
  def after_query(pid, match, fun) do
    id = {__MODULE__, make_ref()}
    # Holds the first exception `match` raises. Unlinked, since `on_exit`
    # runs after the test process exits; teardown stops it.
    {:ok, errors} = Agent.start(fn -> nil end)
    config = %{id: id, pid: pid, match: match, fun: fun, errors: errors}
    :ok = :telemetry.attach(id, @event, &__MODULE__.handle_query/4, config)

    ExUnit.Callbacks.on_exit(fn ->
      # `:ok` means it was still attached: no query matched, `fun` never ran.
      attached? = :telemetry.detach(id) == :ok
      error = Agent.get(errors, & &1)
      :ok = Agent.stop(errors)

      if attached? do
        ExUnit.Assertions.flunk(no_match_message(error))
      end
    end)
  end

  @doc false
  def handle_query(_event, _measurements, metadata, %{id: id, pid: pid} = config) do
    if self() == pid and not Forka.Repo.in_transaction?() and matches?(config, metadata) do
      :telemetry.detach(id)
      config.fun.()
    end

    :ok
  end

  # `:telemetry` detaches a handler that raises and only logs it, so teardown
  # would see it gone and pass. A raising `match` is no match; teardown
  # reports its first exception.
  defp matches?(%{match: match, errors: errors}, metadata) do
    match.(metadata)
  rescue
    exception ->
      stacktrace = __STACKTRACE__

      Agent.update(errors, fn
        nil -> Exception.format(:error, exception, stacktrace)
        first -> first
      end)

      false
  end

  defp no_match_message(nil),
    do: "Race.after_query/3: no matching query outside a transaction"

  defp no_match_message(error),
    do: no_match_message(nil) <> "\n\n`match` raised:\n\n" <> error
end
