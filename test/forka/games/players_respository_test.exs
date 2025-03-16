defmodule Forka.Games.PlayersRepositoryTest do
  use Forka.DataCase

  alias Forka.Games.PlayersRepository
  alias Forka.Games.Player

  describe "get_player/1" do
    test "returns the player with given id" do
      %{id: id, username: username} = player = insert(:player)
      assert %Player{id: ^id, username: ^username} = PlayersRepository.get_player(player.id)
    end

    test "returns nil when player does not exist" do
      assert PlayersRepository.get_player(Ecto.UUID.generate()) == nil
    end
  end
end
