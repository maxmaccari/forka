defmodule Forka.TestHelpers do
  @moduledoc """
  This module defines test helpers.
  """
  alias Forka.Games

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
end
