defmodule Forka.RaceTest do
  use Forka.DataCase, async: true

  alias Forka.Race
  alias Forka.Words.Category

  test "RACE-01: runs callback once after a matching query outside a transaction and detaches" do
    test_pid = self()

    :ok =
      Race.after_query(test_pid, &(&1.source == "categories"), fn ->
        send(test_pid, :raced)
      end)

    Repo.all(Category)
    assert_received :raced

    Repo.all(Category)
    refute_received :raced
  end

  test "RACE-02: skips matching queries inside a transaction and fires after one outside" do
    test_pid = self()

    :ok =
      Race.after_query(test_pid, &(&1.source == "categories"), fn ->
        send(test_pid, :raced)
      end)

    {:ok, _} = Repo.transaction(fn -> Repo.all(Category) end)
    refute_received :raced

    Repo.all(Category)
    assert_received :raced
  end

  test "RACE-03: treats a raising matcher as non-matching without detaching before a later match" do
    test_pid = self()
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    :ok =
      Race.after_query(
        test_pid,
        fn metadata ->
          attempt = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
          if attempt == 1, do: raise("matcher boom")
          metadata.source == "categories"
        end,
        fn -> send(test_pid, :raced) end
      )

    Repo.all(Category)
    refute_received :raced

    Repo.all(Category)
    assert_received :raced
  end

  test "RACE-04: fails teardown when the race callback raises instead of swallowing it" do
    teardown =
      Race.arm(self(), &(&1.source == "categories"), fn ->
        raise "callback boom"
      end)

    Repo.all(Category)

    assert_raise ExUnit.AssertionError, ~r/callback failed.*callback boom/s, teardown
  end

  test "RACE-05: fails teardown when no query matches and includes a raising matcher error" do
    teardown =
      Race.arm(
        self(),
        fn _metadata -> raise "matcher boom" end,
        fn -> :ok end
      )

    Repo.all(Category)

    assert_raise ExUnit.AssertionError,
                 ~r/no matching query outside a transaction.*matcher boom/s,
                 teardown
  end
end
