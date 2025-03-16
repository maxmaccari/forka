defmodule Forka.PlayersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Forka.Players` context.
  """

  def unique_player_email, do: "player#{System.unique_integer()}@example.com"

  def unique_player_username,
    do: String.slice("player#{System.unique_integer([:positive])}", 0, 20)

  def valid_player_password, do: "hello world!"

  def valid_player_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_player_email(),
      username: unique_player_username(),
      password: valid_player_password()
    })
  end

  def player_fixture(attrs \\ %{}) do
    {:ok, player} =
      attrs
      |> valid_player_attributes()
      |> Forka.Players.register_player()

    player
  end

  def extract_player_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
