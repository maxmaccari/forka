defmodule Forka.Games.GameServerTest do
  use Forka.DataCase, async: true

  alias Forka.Games.GameServer
  alias Forka.Games.Game

  alias Forka.Games.Schemas.WordOptions

  @moduletag :capture_log

  setup do
    insert_list(10, :word)
    owner = insert(:player)

    # Create a new game using Game module
    game = insert(:game, owner: owner) |> Repo.preload(:owner)
    game_state = Forka.Games.Schemas.Game.to_game_state(game)

    # Start the game server
    {:ok, pid} = GameServer.start_link(game.id)

    # Allow server to colaborate with same connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    # Subscribe to receive game updates
    GameServer.subscribe(game.id)

    on_exit(fn ->
      # Try to archive the game to properly shut down the process
      try do
        GameServer.archive_game(game.id)
      catch
        :exit, _ -> :ok
      end
    end)

    %{game: game_state, pid: pid}
  end

  describe "start_link/1" do
    test "starts a new game server", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "returns error when attempting to start a server for a non-existent game" do
      non_existent_id = UUID.uuid4()

      # Attempt to start a server for a non-existent game
      assert {:error, :not_found} = GameServer.start_link(non_existent_id)

      # Verify the process doesn't exist
      refute GameServer.exists?(non_existent_id)
      assert GameServer.whereis(non_existent_id) == nil
    end
  end

  describe "exists?/1" do
    test "returns true when the server exists", %{game: game} do
      assert GameServer.exists?(game.id)
    end

    test "returns false when the server doesn't exist" do
      refute GameServer.exists?(UUID.uuid4())
    end
  end

  describe "whereis/1" do
    test "returns the PID when the server exists", %{game: game, pid: pid} do
      assert GameServer.whereis(game.id) == pid
    end

    test "returns :undefined when the server doesn't exist" do
      assert GameServer.whereis(UUID.uuid4()) == nil
    end
  end

  describe "get_game/1" do
    test "returns the current game summary", %{game: game} do
      assert GameServer.get_game(game.id) == Game.to_game_summary(game)
    end
  end

  describe "join_game/2" do
    test "adds a player to the game and sends update via PubSub", %{game: game} do
      player = insert(:player)

      assert :ok = GameServer.join_game(game.id, player.id)

      # Verify we received the update message
      assert_receive {:game_updated, game_summary}
      assert game_summary.players[0].player.id == player.id
    end

    test "returns error when the game is full", %{game: game} do
      # Fill the game with players up to the limit
      for _ <- 1..game.max_players do
        player = insert(:player)
        GameServer.join_game(game.id, player.id)
      end

      flush_messages()

      # Try to add one more player
      extra_player = insert(:player)
      assert {:error, :maximum_players} = GameServer.join_game(game.id, extra_player.id)

      # Don't receive messages in case of errors
      refute_receive {:game_updated, _game_summary}
    end
  end

  describe "leave_game/2" do
    test "removes a player from the game and sends update via PubSub", %{game: game} do
      player = insert(:player)
      GameServer.join_game(game.id, player.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.leave_game(game.id, player.id)

      assert_receive {:game_updated, game_summary}
      refute Map.has_key?(game_summary.players, 0)
    end
  end

  describe "update_settings/2" do
    test "updates game settings and sends update via PubSub", %{game: game} do
      category_ids = [insert(:category).id, insert(:category).id]
      settings = %{word_options: %{language: "pt", category_ids: category_ids}}

      assert :ok = GameServer.update_settings(game.id, settings)

      assert_receive {:game_updated, game_summary}

      assert %WordOptions{
               language: "pt",
               category_ids: ^category_ids
             } = game_summary.word_options
    end

    test "returns error when game is not in lobby state", %{game: game} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)
      GameServer.start_game(game.id)

      flush_messages()

      # Try to update settings after game started
      settings = %{word_options: %{language: "es"}}
      assert {:error, :game_not_in_lobby} = GameServer.update_settings(game.id, settings)

      # Don't receive messages in case of errors
      refute_receive {:game_updated, _game_summary}
    end
  end

  describe "start_game/1" do
    test "starts the game and sends update via PubSub", %{game: game} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      flush_messages()

      assert :ok = GameServer.start_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing
    end

    test "filters words by language when starting a game", %{game: game} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      # Insert a Portuguese word
      insert(:word,
        text: "gato",
        hint: "Mia",
        category: insert(:category, language: "pt", name: "animals")
      )

      # Set language option to Portuguese
      GameServer.update_settings(game.id, %{word_options: %{language: "pt"}})

      flush_messages()

      # Start the game
      assert :ok = GameServer.start_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing

      # Get the current player
      current_player_id = game_summary.current_player_id

      # Try to guess the Portuguese word "gato" letter by letter
      letters = ["g", "a", "t", "o"]

      Enum.each(letters, fn letter ->
        assert :ok = GameServer.guess(game.id, current_player_id, letter)
        assert_receive {:game_updated, _updated_summary}
      end)

      # Get the final game state
      final_summary = GameServer.get_game(game.id)
      assert final_summary.game_status == :finished
    end

    test "filters words by categories when starting a game", %{game: game} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      # Insert a Portuguese word
      category_1 = insert(:category)
      category_2 = insert(:category)

      insert(:word,
        text: "gato",
        hint: "Mia",
        category: category_1
      )

      # Set language option to Portuguese
      GameServer.update_settings(game.id, %{
        word_options: %{category_ids: [category_1.id, category_2.id]}
      })

      flush_messages()

      # Start the game
      assert :ok = GameServer.start_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing

      # Get the current player
      current_player_id = game_summary.current_player_id

      # Try to guess the Portuguese word "gato" letter by letter
      letters = ["g", "a", "t", "o"]

      Enum.each(letters, fn letter ->
        assert :ok = GameServer.guess(game.id, current_player_id, letter)
        assert_receive {:game_updated, _updated_summary}
      end)

      # Get the final game state
      final_summary = GameServer.get_game(game.id)
      assert final_summary.game_status == :finished
    end

    test "returns error when trying to start a game with insufficient players", %{game: game} do
      player = insert(:player)
      GameServer.join_game(game.id, player.id)

      flush_messages()

      # Try to start the game with insufficient players
      assert {:error, :game_not_ready} = GameServer.start_game(game.id)

      # Verify game is still in lobby state
      game_summary = GameServer.get_game(game.id)
      assert game_summary.game_status == :lobby

      # Don't receive messages in case of errors
      refute_receive {:game_updated, _game_summary}
    end
  end

  describe "give_up_game/2" do
    test "allows a player to give up and sends update via PubSub", %{game: game} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      # Start the game
      GameServer.start_game(game.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.give_up_game(game.id, player2.id)

      assert_receive {:game_updated, game_summary}

      player2 =
        game_summary.players
        |> Map.values()
        |> Enum.find(&(&1.player.id == player2.id))

      assert player2.lives == 0
      assert player2.status == :dead
    end

    test "updates game to game_over when all players give up", %{game: game} do
      # Add players to the game
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      # Start the game
      :ok = GameServer.start_game(game.id)

      # Clear message inbox
      flush_messages()

      # First player gives up
      assert :ok = GameServer.give_up_game(game.id, player1.id)
      assert_receive {:game_updated, _game_summary}

      # Game should still be in playing state
      game_summary = GameServer.get_game(game.id)
      assert game_summary.game_status == :playing

      # Second player gives up
      assert :ok = GameServer.give_up_game(game.id, player2.id)
      assert_receive {:game_updated, updated_summary}

      # Game should now be in game_over state
      assert updated_summary.game_status == :game_over
    end
  end

  describe "guess/3" do
    test "processes a guess attempt and sends update via PubSub", %{game: game} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      :ok = GameServer.start_game(game.id)

      # Clear message inbox
      flush_messages()

      # Get the game summary to know which player is active
      game_summary = GameServer.get_game(game.id)
      active_player_id = game_summary.current_player_id

      # Make a guess with letter 'a'
      assert :ok = GameServer.guess(game.id, active_player_id, "a")

      assert_receive {:game_updated, _game_summary}
    end

    test "returns error when it's not the player's turn", %{game: game} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)
      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      GameServer.start_game(game.id)

      # Get the game summary to know which player is NOT active
      game_summary = GameServer.get_game(game.id)
      active_player_id = game_summary.current_player_id

      inactive_player_id =
        game_summary.players
        |> Map.values()
        |> Enum.map(& &1.player.id)
        |> Enum.find(&(&1 != active_player_id))

      # Try to guess with the inactive player
      assert {:error, :not_player_turn} = GameServer.guess(game.id, inactive_player_id, "a")
    end
  end

  describe "transfer_ownership/2" do
    test "transfers game ownership and sends update via PubSub", %{game: game} do
      # Add a player to transfer ownership to
      player = insert(:player)
      GameServer.join_game(game.id, player.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.transfer_ownership(game.id, player.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.owner.id == player.id
    end
  end

  describe "restart_game/1" do
    test "restarts the game and sends update via PubSub", %{game: game} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)

      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      GameServer.start_game(game.id)

      # Give up players to get a game over
      GameServer.give_up_game(game.id, player1.id)
      GameServer.give_up_game(game.id, player2.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.restart_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :lobby
    end

    test "cannot restart an ongoing game", %{game: game} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_game(game.id, player1.id)

      player2 = insert(:player)
      GameServer.join_game(game.id, player2.id)

      GameServer.start_game(game.id)

      # Clear message inbox
      flush_messages()

      # Try to restart an ongoing game
      assert {:error, :game_in_progress} = GameServer.restart_game(game.id)

      # Verify no game update was sent
      refute_receive {:game_updated, _}
    end
  end

  describe "archive_game/1" do
    test "archives the game, sends update via PubSub and terminates the server", %{game: game} do
      assert :ok = GameServer.archive_game(game.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :archived

      # Verify the server was terminated
      # Give time for the process to terminate
      Process.sleep(100)
      refute GameServer.exists?(game.id)
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "manages subscriptions for game updates", %{game: game} do
      # We're already subscribed in setup, so let's unsubscribe
      assert :ok = GameServer.unsubscribe(game.id)

      # Add a player, which should generate an update
      player = insert(:player)
      GameServer.join_game(game.id, player.id)

      # We shouldn't receive the update after unsubscribing
      refute_receive {:game_updated, _}

      # Subscribe again
      assert :ok = GameServer.subscribe(game.id)

      # Make another change
      GameServer.leave_game(game.id, player.id)

      # Now we should receive the update
      assert_receive {:game_updated, _}
    end
  end

  describe "timeout handling" do
    test "archives the game and terminates the server after timeout", %{game: game, pid: pid} do
      # Send a timeout message directly to the server process
      # This simulates what would happen after 30 minutes of inactivity
      send(pid, :timeout)

      # Verify we receive a game update with archived status
      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :archived

      # Give time for the process to terminate
      Process.sleep(100)

      # Verify the server was terminated
      refute GameServer.exists?(game.id)
    end

    test "archives the game and terminates the server after timeout when in playing state", %{
      game: game,
      pid: pid
    } do
      # We will put the game in playing state
      player1 = insert(:player)
      player2 = insert(:player)
      :ok = GameServer.join_game(game.id, player1.id)
      :ok = GameServer.join_game(game.id, player2.id)
      :ok = GameServer.start_game(game.id)

      # Clear message inbox from game start
      flush_messages()

      # Send a timeout message directly to the server process
      # This simulates what would happen after 30 minutes of inactivity
      send(pid, :timeout)

      # Verify we receive a game update with archived status
      # We don't receive any message because the game is in playing state
      # and Game.archive_game/1 returns {:error, :game_in_progress}
      refute_receive {:game_updated, _}

      # Give time for the process to terminate
      Process.sleep(100)

      # Verify the server was terminated
      refute GameServer.exists?(game.id)
    end
  end

  # Helper function to clear the message inbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
