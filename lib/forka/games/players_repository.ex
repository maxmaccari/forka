defmodule Forka.Games.PlayersRepository do
  @moduledoc """
  Repository module for managing player data.
  Provides functions to retrieve and manipulate player records.
  """

  alias Forka.Games.Player
  alias Forka.Repo

  @doc """
  Gets a player by ID.

  ## Parameters

    * `id` - The UUID of the player to retrieve

  ## Examples

      iex> get_player("123e4567-e89b-12d3-a456-426614174000")
      %Player{}

      iex> get_player("nonexistent-uuid")
      nil

  ## Returns

  The Player struct if found, nil otherwise.
  """
  def get_player(id) do
    Repo.get(Player, id)
  end
end
