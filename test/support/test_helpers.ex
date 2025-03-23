defmodule Forka.TestHelpers do
  @moduledoc """
  This module defines test helpers.
  """
  alias Forka.Games

  import ExUnit.Assertions

  def extract_token_from_email(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def build_games_player(username) do
    %Games.Schemas.Player{
      id: UUID.uuid4(),
      username: username
    }
  end

  # Helper function to assert on the last events from the current tick
  def assert_last_events(game, expected_events) do
    current_tick = game.tick

    # Get events from the current tick
    current_tick_events =
      game.events
      |> Enum.filter(fn event -> event.tick == current_tick end)
      |> Enum.map(fn event -> Map.take(event, [:type, :payload]) end)

    # Assert that the expected events match the actual events
    assert Enum.count(current_tick_events) == Enum.count(expected_events)

    Enum.zip(current_tick_events, expected_events)
    |> Enum.all?(fn {actual, expected} ->
      Enum.all?(expected, fn {key, value} ->
        Map.get(actual, key) == value
      end)
    end)
  end

  # Helper function to clear the message inbox
  def flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
