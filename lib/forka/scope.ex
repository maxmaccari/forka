defmodule Forka.Scope do
  @moduledoc """
  Defines the authenticated player scope passed to Context functions.
  """

  alias Forka.Players.Player

  @type t :: %__MODULE__{player: Player.t() | nil}

  defstruct [:player]

  @doc "Builds a `%Forka.Scope{}` for an authenticated player, or returns `nil` for guests."
  @spec for_player(Player.t() | nil) :: t() | nil
  def for_player(%Player{} = player), do: %__MODULE__{player: player}
  def for_player(nil), do: nil
end
