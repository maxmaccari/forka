defmodule Forka.Games.GameServerTest do
  use Forka.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Forka.Games.Core
  alias Forka.Games.GameServer
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Game
  alias Forka.Games.Schemas.WordOptions

  import Forka.TestHelpers

  @moduletag :capture_log

  setup do
    insert_list(10, :word)
    owner = insert(:player)

    # Create a new game using Game module
    game = insert(:game, owner: owner) |> Repo.preload([:owner, :events])
    game_state = Game.to_game_state(game)

    # Start the game server
    {:ok, pid} = GameServer.start_link(game.id)

    # Allow server to colaborate with same connection
    Sandbox.allow(Repo, self(), pid)

    # Subscribe to receive game updates
    GameServer.subscribe(game.id)

    on_exit(fn ->
      # Try to archive the game to properly shut down the process
      try do
        GameServer.archive_game(game_state.id, game_state.owner.id)
      catch
        :exit, _ -> :ok
      end
    end)

    %{game_state: game_state, pid: pid}
  end

  describe "start_link/1" do
    test "starts a new game server", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "doesn't start a server when the game is archived" do
      # Create an archived game
      owner = insert(:player)
      archived_game_state = insert(:game, owner: owner, status: :archived) |> Repo.preload(:owner)

      # Attempt to start a server for the archived game
      assert {:error, :game_archived} = GameServer.start_link(archived_game_state.id)

      # Verify the process doesn't exist
      refute GameServer.exists?(archived_game_state.id)
      assert GameServer.whereis(archived_game_state.id) == nil
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
    test "returns true when the server exists", %{game_state: game_state} do
      assert GameServer.exists?(game_state.id)
    end

    test "returns false when the server doesn't exist" do
      refute GameServer.exists?(UUID.uuid4())
    end
  end

  describe "whereis/1" do
    test "returns the PID when the server exists", %{game_state: game_state, pid: pid} do
      assert GameServer.whereis(game_state.id) == pid
    end

    test "returns :undefined when the server doesn't exist" do
      assert GameServer.whereis(UUID.uuid4()) == nil
    end
  end

  describe "get_game/1" do
    test "returns the current game summary", %{game_state: game_state} do
      assert GameServer.get_game(game_state.id) == Core.to_game_summary(game_state)
    end

    test "returns all the current game summary with all events", %{game_state: game_state} do
      assert GameServer.get_game(game_state.id, load_all_events: true) ==
               Core.to_game_summary(game_state, load_all_events: true)
    end
  end

  describe "join_room/2" do
    test "adds a player to the game and sends update via PubSub", %{game_state: game_state} do
      player = insert(:player)

      assert {:ok, :joined} = GameServer.join_room(game_state.id, player.id)

      # Verify we received the update message
      assert_receive {:game_updated, game_summary}
      assert game_summary.players[0].player.id == player.id
    end

    test "persists the game state after joining", %{game_state: game_state} do
      player = insert(:player)

      assert {:ok, :joined} = GameServer.join_room(game_state.id, player.id)

      # Verify the game state was persisted
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)

      assert Enum.any?(persisted_summary.players, fn {_, player_state} ->
               player_state.player.id == player.id
             end)
    end

    test "returns error when the game is full", %{game_state: game_state} do
      # Fill the game with players up to the limit
      for _ <- 1..game_state.max_players do
        player = insert(:player)
        GameServer.join_room(game_state.id, player.id)
      end

      flush_messages()

      # Try to add one more player
      extra_player = insert(:player)
      assert {:error, :maximum_players} = GameServer.join_room(game_state.id, extra_player.id)

      # Don't receive messages in case of errors
      refute_receive {:game_updated, _game_summary}
    end
  end

  describe "leave_game/2" do
    test "removes a player from the game and sends update via PubSub", %{game_state: game_state} do
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.leave_game(game_state.id, player.id)

      assert_receive {:game_updated, game_summary}
      refute Map.has_key?(game_summary.players, 0)
    end

    test "persists the game state after leaving", %{game_state: game_state} do
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      assert :ok = GameServer.leave_game(game_state.id, player.id)

      # Verify the game state was persisted
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)

      refute Enum.any?(persisted_summary.players, fn {_, player_state} ->
               player_state.player.id == player.id
             end)
    end
  end

  describe "update_settings/3" do
    test "updates game settings and sends update via PubSub", %{game_state: game_state} do
      category_ids = [
        insert(:category, language: "pt").id,
        insert(:category, language: "pt").id
      ]

      settings = %{word_options: %{language: "pt", category_ids: category_ids}}

      assert :ok = GameServer.update_settings(game_state.id, game_state.owner.id, settings)

      assert_receive {:game_updated, game_summary}

      assert %WordOptions{
               language: "pt",
               category_ids: ^category_ids
             } = game_summary.word_options
    end

    test "persists the game state after updating settings", %{game_state: game_state} do
      category_ids = [
        insert(:category, language: "pt").id,
        insert(:category, language: "pt").id
      ]

      settings = %{word_options: %{language: "pt", category_ids: category_ids}}

      assert :ok = GameServer.update_settings(game_state.id, game_state.owner.id, settings)

      # Verify the gate state was persisted
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.word_options.language == "pt"
      assert persisted_summary.word_options.category_ids == category_ids
    end

    test "returns error when game is not in lobby state", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)
      GameServer.start_game(game_state.id, game_state.owner.id)

      flush_messages()

      # Try to update settings after game started
      settings = %{word_options: %{language: "pt"}}

      assert {:error, :game_not_in_lobby} =
               GameServer.update_settings(game_state.id, game_state.owner.id, settings)

      # Don't receive messages in case of errors
      refute_receive {:game_updated, _game_summary}
    end
  end

  describe "start_game/2" do
    test "starts the game and sends update via PubSub", %{game_state: game_state} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      flush_messages()

      assert :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing
    end

    test "persists the game state after starting", %{game_state: game_state} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      assert :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      # Verify the game state was persisted
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :playing
    end

    test "filters words by language when starting a game", %{game_state: game_state} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      # Insert Portuguese words
      pt_category = insert(:category, language: "pt", name: "animals")

      for text <- ~w(gato pato rato sapo) do
        insert(:word, text: text, category: pt_category)
      end

      # Set language option to Portuguese
      GameServer.update_settings(game_state.id, game_state.owner.id, %{
        word_options: %{language: "pt"}
      })

      flush_messages()

      # Start the game
      assert :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing

      {:ok, persisted} = Repository.get_game_state(game_state.id)
      assert map_size(persisted.game_words) == 4
      assert Enum.all?(Map.values(persisted.game_words), &(&1.word.language == "pt"))

      # Get the current player
      current_player_id = game_summary.current_player_id

      for idx <- 0..3 do
        letters = persisted.game_words[idx].word.text |> String.graphemes() |> Enum.uniq()

        Enum.each(letters, fn letter ->
          assert :ok = GameServer.guess(game_state.id, current_player_id, letter)
          assert_receive {:game_updated, _updated_summary}
        end)
      end

      # Get the final game state
      final_summary = GameServer.get_game(game_state.id)
      assert final_summary.game_status == :finished
    end

    test "filters words by categories when starting a game", %{game_state: game_state} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      # Insert words across two categories
      category_1 = insert(:category)
      category_2 = insert(:category)

      for text <- ~w(gato pato) do
        insert(:word, text: text, category: category_1)
      end

      for text <- ~w(rato sapo) do
        insert(:word, text: text, category: category_2)
      end

      # Set category filter
      GameServer.update_settings(game_state.id, game_state.owner.id, %{
        word_options: %{category_ids: [category_1.id, category_2.id]}
      })

      flush_messages()

      # Start the game
      assert :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :playing

      {:ok, persisted} = Repository.get_game_state(game_state.id)
      assert map_size(persisted.game_words) == 4

      assert Enum.all?(
               Map.values(persisted.game_words),
               &(&1.word.category in [category_1.name, category_2.name])
             )

      # Get the current player
      current_player_id = game_summary.current_player_id

      for idx <- 0..3 do
        letters = persisted.game_words[idx].word.text |> String.graphemes() |> Enum.uniq()

        Enum.each(letters, fn letter ->
          assert :ok = GameServer.guess(game_state.id, current_player_id, letter)
          assert_receive {:game_updated, _updated_summary}
        end)
      end

      # Get the final game state
      final_summary = GameServer.get_game(game_state.id)
      assert final_summary.game_status == :finished
    end

    test "returns error when trying to start a game with insufficient players", %{
      game_state: game_state
    } do
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      flush_messages()

      # Try to start the game with insufficient players
      assert {:error, :game_not_ready} =
               GameServer.start_game(game_state.id, game_state.owner.id)

      # Verify game is still in lobby state
      game_summary = GameServer.get_game(game_state.id)
      assert game_summary.game_status == :lobby

      # Don't receive messages in case of errors
      refute_receive {:game_updated, _game_summary}
    end

    test "REQ-04 & EDGE-01: keeps room in lobby with insufficient_words error and no broadcast when pool is too small",
         %{game_state: game_state} do
      player1 = insert(:player)
      player2 = insert(:player)
      {:ok, :joined} = GameServer.join_room(game_state.id, player1.id)
      {:ok, :joined} = GameServer.join_room(game_state.id, player2.id)

      pt_cat = insert(:category, name: "Pequena", language: "pt")
      insert(:word, text: "café", category: pt_cat)
      insert(:word, text: "cafe", category: pt_cat)
      insert(:word, text: "gato", category: pt_cat)
      insert(:word, text: "pato", category: pt_cat)
      insert(:word, text: "straße", category: pt_cat)
      Repo.insert!(%Forka.Words.Word{text: "   ", category_id: pt_cat.id})

      :ok =
        GameServer.update_settings(game_state.id, game_state.owner.id, %{
          word_options: %{language: "pt", category_ids: [pt_cat.id]}
        })

      flush_messages()
      before_state = Repository.get_game_state(game_state.id)

      assert {:error, {:insufficient_words, %{available: 3, required: 4}}} =
               GameServer.start_game(game_state.id, game_state.owner.id)

      summary = GameServer.get_game(game_state.id)
      assert summary.game_status == :lobby
      assert Repository.get_game_state(game_state.id) == before_state
      refute_receive {:game_updated, _}
    end

    test "REQ-03 & REQ-05: validates 2-player and 6-player limits and re-validates as roster changes" do
      owner = insert(:player)
      pt_cat = insert(:category, name: "Limite", language: "pt")

      for text <- ~w(alfa bravo charlie delta) do
        insert(:word, text: text, category: pt_cat)
      end

      game =
        insert(:game,
          owner: owner,
          max_players: 6,
          word_options: %WordOptions{language: "pt", category_ids: [pt_cat.id]}
        )

      {:ok, pid} = GameServer.start_link(game.id)
      Sandbox.allow(Repo, self(), pid)

      on_exit(fn ->
        try do
          GameServer.archive_game(game.id, owner.id)
        catch
          :exit, _ -> :ok
        end
      end)

      p1 = insert(:player)
      p2 = insert(:player)
      p3 = insert(:player)

      {:ok, :joined} = GameServer.join_room(game.id, p1.id)
      assert {:error, :game_not_ready} = GameServer.start_game(game.id, owner.id)

      # 2 players with 4 distinct words -> ready; 3rd player joins -> needs 6 -> blocked
      {:ok, :joined} = GameServer.join_room(game.id, p2.id)
      {:ok, :joined} = GameServer.join_room(game.id, p3.id)

      assert {:error, {:insufficient_words, %{available: 4, required: 6}}} =
               GameServer.start_game(game.id, owner.id)

      assert GameServer.get_game(game.id).game_status == :lobby

      # 3rd player leaves -> back to 2 players -> 4 words is enough again
      :ok = GameServer.leave_game(game.id, p3.id)
      assert :ok = GameServer.start_game(game.id, owner.id)

      {:ok, started_state} = Repository.get_game_state(game.id)
      assert started_state.status == :playing
      assert map_size(started_state.game_words) == 4
    end

    test "REQ-03: enforces 12 distinct playable words for 6-player match and blocks 7th player" do
      owner = insert(:player)
      pt_cat = insert(:category, name: "Seis", language: "pt")

      for text <- ~w(um dois tres quatro cinco seis sete oito nove dez onze) do
        insert(:word, text: text, category: pt_cat)
      end

      game =
        insert(:game,
          owner: owner,
          max_players: 6,
          word_options: %WordOptions{language: "pt", category_ids: [pt_cat.id]}
        )

      {:ok, pid} = GameServer.start_link(game.id)
      Sandbox.allow(Repo, self(), pid)

      on_exit(fn ->
        try do
          GameServer.archive_game(game.id, owner.id)
        catch
          :exit, _ -> :ok
        end
      end)

      for _ <- 1..6 do
        p = insert(:player)
        assert {:ok, :joined} = GameServer.join_room(game.id, p.id)
      end

      seventh = insert(:player)
      assert {:error, :maximum_players} = GameServer.join_room(game.id, seventh.id)

      assert {:error, {:insufficient_words, %{available: 11, required: 12}}} =
               GameServer.start_game(game.id, owner.id)

      assert GameServer.get_game(game.id).game_status == :lobby

      insert(:word, text: "doze", category: pt_cat)
      assert :ok = GameServer.start_game(game.id, owner.id)

      {:ok, started_state} = Repository.get_game_state(game.id)
      assert started_state.status == :playing
      assert map_size(started_state.game_words) == 12
    end
  end

  describe "give_up_game/2" do
    test "allows a player to give up and sends update via PubSub", %{game_state: game_state} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      # Start the game
      GameServer.start_game(game_state.id, game_state.owner.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.give_up_game(game_state.id, player2.id)

      assert_receive {:game_updated, game_summary}

      player2 =
        game_summary.players
        |> Map.values()
        |> Enum.find(&(&1.player.id == player2.id))

      assert player2.lives == 0
      assert player2.status == :dead
    end

    test "persists the game state after player gives up", %{game_state: game_state} do
      # Add players to have at least 2 players
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      # Start the game
      GameServer.start_game(game_state.id, game_state.owner.id)

      assert :ok = GameServer.give_up_game(game_state.id, player2.id)

      # Verify the game state was persisted
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)

      player2_state =
        persisted_summary.players
        |> Map.values()
        |> Enum.find(&(&1.player.id == player2.id))

      assert player2_state.lives == 0
      assert player2_state.status == :dead
    end

    test "updates game to game_over when all players give up", %{game_state: game_state} do
      # Add players to the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      # Start the game
      :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      # Clear message inbox
      flush_messages()

      # First player gives up
      assert :ok = GameServer.give_up_game(game_state.id, player1.id)
      assert_receive {:game_updated, _game_summary}

      # Game should still be in playing state
      game_summary = GameServer.get_game(game_state.id)
      assert game_summary.game_status == :playing

      # Second player gives up
      assert :ok = GameServer.give_up_game(game_state.id, player2.id)
      assert_receive {:game_updated, updated_summary}

      # Game should now be in game_over state
      assert updated_summary.game_status == :game_over

      # Verify the game state was persisted with game_over status
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :game_over
    end
  end

  describe "guess/3" do
    test "processes a guess attempt and sends update via PubSub", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      # Clear message inbox
      flush_messages()

      # Get the game summary to know which player is active
      game_summary = GameServer.get_game(game_state.id)
      active_player_id = game_summary.current_player_id

      # Make a guess with letter 'a'
      assert :ok = GameServer.guess(game_state.id, active_player_id, "a")

      assert_receive {:game_updated, _game_summary}
    end

    test "persists the game state after a guess", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      # Get the game summary to know which player is active
      game_summary = GameServer.get_game(game_state.id)
      active_player_id = game_summary.current_player_id

      # Get the initial state
      {:ok, initial_game} = Repository.get_game_state(game_state.id)
      initial_summary = Core.to_game_summary(initial_game)
      initial_guesses = initial_summary.guesses

      # Make a guess with letter 'a'
      assert :ok = GameServer.guess(game_state.id, active_player_id, "a")

      # Verify the game state was persisted with the new guess
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.guesses != initial_guesses
      assert "a" in Enum.map(persisted_summary.guesses, & &1.letter)
    end

    test "returns error when it's not the player's turn", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)
      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      GameServer.start_game(game_state.id, game_state.owner.id)

      # Get the game summary to know which player is NOT active
      game_summary = GameServer.get_game(game_state.id)
      active_player_id = game_summary.current_player_id

      inactive_player_id =
        game_summary.players
        |> Map.values()
        |> Enum.map(& &1.player.id)
        |> Enum.find(&(&1 != active_player_id))

      # Try to guess with the inactive player
      assert {:error, :not_player_turn} = GameServer.guess(game_state.id, inactive_player_id, "a")
    end

    test "R-03: persists sixth-miss elimination with locked score and ends in game_over when all players fall" do
      category = insert(:category, name: "Deterministic", language: "en")
      for text <- ["cat", "act", "tac", "at"], do: insert(:word, text: text, category: category)

      owner = insert(:player)
      player1 = insert(:player)
      player2 = insert(:player)

      dedicated_game =
        insert(:game,
          owner: owner,
          word_options: WordOptions.new(%{language: "en", category_ids: [category.id]})
        )

      pid = start_supervised!({GameServer, dedicated_game.id}, id: :sixth_miss_server)
      Sandbox.allow(Repo, self(), pid)

      assert {:ok, :joined} = GameServer.join_room(dedicated_game.id, player1.id)
      assert {:ok, :joined} = GameServer.join_room(dedicated_game.id, player2.id)
      assert :ok = GameServer.start_game(dedicated_game.id, owner.id)

      initial_summary = GameServer.get_game(dedicated_game.id)
      first_id = initial_summary.current_player_id

      second_id =
        initial_summary.players
        |> Map.values()
        |> Enum.map(& &1.player.id)
        |> Enum.find(&(&1 != first_id))

      # First player earns 10 points before alternating 11 misses (6 for first, 5 for second)
      assert :ok = GameServer.guess(dedicated_game.id, first_id, "a")

      for {pid_turn, letter} <- [
            {first_id, "z"},
            {second_id, "q"},
            {first_id, "w"},
            {second_id, "j"},
            {first_id, "k"},
            {second_id, "v"},
            {first_id, "p"},
            {second_id, "u"},
            {first_id, "m"},
            {second_id, "n"},
            {first_id, "r"}
          ] do
        assert :ok = GameServer.guess(dedicated_game.id, pid_turn, letter)
      end

      mid_summary = GameServer.get_game(dedicated_game.id)
      assert mid_summary.game_status == :playing
      assert mid_summary.current_player_id == second_id

      first_state =
        mid_summary.players |> Map.values() |> Enum.find(&(&1.player.id == first_id))

      assert %{status: :dead, lives: 0, score: 10} = first_state
      assert {:error, :not_player_turn} = GameServer.guess(dedicated_game.id, first_id, "c")

      # Second player takes 6th miss -> all players out -> persisted :game_over with locked scores
      assert :ok = GameServer.guess(dedicated_game.id, second_id, "s")

      final_summary = GameServer.get_game(dedicated_game.id)
      assert final_summary.game_status == :game_over
      assert final_summary.current_player_id == nil

      {:ok, persisted} = Repository.get_game_state(dedicated_game.id)
      assert persisted.status == :game_over
      assert persisted.current_game_player_index == nil
      assert persisted.current_game_word_index == nil

      persisted_first =
        persisted.game_players |> Map.values() |> Enum.find(&(&1.player.id == first_id))

      persisted_second =
        persisted.game_players |> Map.values() |> Enum.find(&(&1.player.id == second_id))

      assert %{status: :dead, lives: 0, score: 10} = persisted_first
      assert %{status: :dead, lives: 0, score: 0} = persisted_second
    end
  end

  describe "transfer_ownership/3" do
    test "transfers game ownership and sends update via PubSub", %{game_state: game_state} do
      # Add a player to transfer ownership to
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.transfer_ownership(game_state.id, game_state.owner.id, player.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.owner.id == player.id
    end

    test "persists the game state after ownership transfer", %{game_state: game_state} do
      # Add a player to transfer ownership to
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      assert :ok = GameServer.transfer_ownership(game_state.id, game_state.owner.id, player.id)

      # Verify the game state was persisted with new owner
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.owner.id == player.id
    end
  end

  describe "restart_game/2" do
    test "restarts the game and sends update via PubSub", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)

      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      GameServer.start_game(game_state.id, game_state.owner.id)

      # Give up players to get a game over
      GameServer.give_up_game(game_state.id, player1.id)
      GameServer.give_up_game(game_state.id, player2.id)

      # Clear message inbox
      flush_messages()

      assert :ok = GameServer.restart_game(game_state.id, game_state.owner.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :lobby
    end

    test "persists the game state after restart", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)

      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      GameServer.start_game(game_state.id, game_state.owner.id)

      # Give up players to get a game over
      GameServer.give_up_game(game_state.id, player1.id)
      GameServer.give_up_game(game_state.id, player2.id)

      assert :ok = GameServer.restart_game(game_state.id, game_state.owner.id)

      # Verify the game state was persisted with lobby status
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :lobby
      assert persisted_summary.guesses == []
    end

    test "cannot restart an ongoing game", %{game_state: game_state} do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)

      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      GameServer.start_game(game_state.id, game_state.owner.id)

      # Clear message inbox
      flush_messages()

      # Try to restart an ongoing game
      assert {:error, :game_in_progress} =
               GameServer.restart_game(game_state.id, game_state.owner.id)

      # Verify no game update was sent
      refute_receive {:game_updated, _}
    end
  end

  describe "archive_game/2" do
    test "archives the game, sends update via PubSub and terminates the server", %{
      game_state: game_state
    } do
      assert :ok = GameServer.archive_game(game_state.id, game_state.owner.id)

      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :archived

      # Verify the server was terminated
      # Give time for the process to terminate
      Process.sleep(100)
      refute GameServer.exists?(game_state.id)
    end

    test "persists the game state after archiving", %{game_state: game_state} do
      assert :ok = GameServer.archive_game(game_state.id, game_state.owner.id)

      # Verify the game state was persisted with archived status
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :archived
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "manages subscriptions for game updates", %{game_state: game_state} do
      # We're already subscribed in setup, so let's unsubscribe
      assert :ok = GameServer.unsubscribe(game_state.id)

      # Add a player, which should generate an update
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      # We shouldn't receive the update after unsubscribing
      refute_receive {:game_updated, _}

      # Subscribe again
      assert :ok = GameServer.subscribe(game_state.id)

      # Make another change
      GameServer.leave_game(game_state.id, player.id)

      # Now we should receive the update
      assert_receive {:game_updated, _}
    end

    test "subscription persists across server restarts", %{game_state: game_state} do
      # We're already subscribed in setup

      # Stop the server
      pid = GameServer.whereis(game_state.id)
      GenServer.stop(pid, :normal)

      # Wait for the server to stop
      Process.sleep(100)
      refute Process.alive?(pid)

      # Start the server again
      {:ok, pid} = GameServer.start_link(game_state.id)
      Sandbox.allow(Repo, self(), pid)

      # Make a change to the game
      player = insert(:player)
      GameServer.join_room(game_state.id, player.id)

      # We should still receive updates without having to resubscribe
      assert_receive {:game_updated, _}
    end
  end

  describe "timeout handling" do
    test "archives the game and terminates the server after timeout", %{
      game_state: game_state,
      pid: pid
    } do
      # Send a timeout message directly to the server process
      # This simulates what would happen after 30 minutes of inactivity
      send(pid, :timeout)

      # Verify we receive a game update with archived status
      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :archived

      # Give time for the process to terminate
      Process.sleep(100)

      # Verify the server was terminated
      refute GameServer.exists?(game_state.id)

      # Verify the game state was persisted with archived status
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :archived
    end

    test "archives the game and terminates the server after timeout when in playing state", %{
      game_state: game_state,
      pid: pid
    } do
      # We will put the game in playing state
      player1 = insert(:player)
      player2 = insert(:player)
      {:ok, :joined} = GameServer.join_room(game_state.id, player1.id)
      {:ok, :joined} = GameServer.join_room(game_state.id, player2.id)
      :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      # Clear message inbox from game start
      flush_messages()

      # Send a timeout message directly to the server process
      # This simulates what would happen after 30 minutes of inactivity
      send(pid, :timeout)

      # Verify we receive a game update with archived status
      # We don't receive any message because the game is in playing state
      # and Core.archive_game/1 returns {:error, :game_in_progress}
      refute_receive {:game_updated, _}

      # Give time for the process to terminate
      Process.sleep(100)

      # Verify the server was terminated
      refute GameServer.exists?(game_state.id)
    end
  end

  describe "persistence" do
    test "persists the game as archived when terminated due to timeout", %{
      game_state: game_state,
      pid: pid
    } do
      # Clear message inbox
      flush_messages()

      # Send a timeout message directly to the server process
      # This simulates what would happen after 30 minutes of inactivity
      send(pid, :timeout)

      # Verify we receive a game update with archived status
      assert_receive {:game_updated, game_summary}
      assert game_summary.game_status == :archived

      # Give time for the process to terminate
      Process.sleep(100)

      # Verify the server was terminated
      refute GameServer.exists?(game_state.id)

      # Verify the game state was persisted with archived status
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :archived
    end

    test "persists the game state when terminated in playing state", %{
      game_state: game_state,
      pid: pid
    } do
      # Add players and start the game
      player1 = insert(:player)
      GameServer.join_room(game_state.id, player1.id)

      player2 = insert(:player)
      GameServer.join_room(game_state.id, player2.id)

      # Start the game to put it in playing state
      :ok = GameServer.start_game(game_state.id, game_state.owner.id)

      # Make a guess to ensure we have some game progress
      game_summary = GameServer.get_game(game_state.id)
      active_player_id = game_summary.current_player_id
      GameServer.guess(game_state.id, active_player_id, "a")

      # Get the current state before termination
      pre_termination_summary = GameServer.get_game(game_state.id)
      assert pre_termination_summary.game_status == :playing

      # Clear message inbox
      flush_messages()

      # Send a timeout message directly to the server process
      send(pid, :timeout)

      # Don't receive nothing when the game halt
      refute_receive {:game_updated, _game_summary}

      # Give time for the process to terminate
      Process.sleep(100)

      # Verify the server was terminated
      refute GameServer.exists?(game_state.id)

      # Verify the game state was persisted with archived status
      {:ok, persisted_game_state} = Repository.get_game_state(game_state.id)
      persisted_summary = Core.to_game_summary(persisted_game_state)
      assert persisted_summary.game_status == :playing

      # Start a new server for the same game to verify state is loaded correctly
      {:ok, new_pid} = GameServer.start_link(game_state.id)

      # Allow server to collaborate with same connection
      Sandbox.allow(Repo, self(), new_pid)

      # Verify the loaded state matches what was persisted
      loaded_summary = GameServer.get_game(game_state.id)
      assert loaded_summary.game_status == :playing
    end
  end

  describe "REQ-03: command boundary authorization" do
    test "REQ-03: rejects unauthorized owner commands without saving or broadcasting", %{
      game_state: game_state
    } do
      player1 = insert(:player)
      player2 = insert(:player)
      outsider = insert(:player)

      assert {:ok, :joined} = GameServer.join_room(game_state.id, player1.id)
      assert {:ok, :joined} = GameServer.join_room(game_state.id, player2.id)
      flush_messages()

      assert {:error, :unauthorized} = GameServer.start_game(game_state.id, player1.id)
      assert {:error, :unauthorized} = GameServer.start_game(game_state.id, outsider.id)

      assert {:error, :unauthorized} =
               GameServer.transfer_ownership(game_state.id, player1.id, player2.id)

      assert {:error, :unauthorized} = GameServer.restart_game(game_state.id, player1.id)
      assert {:error, :unauthorized} = GameServer.archive_game(game_state.id, player1.id)

      refute_receive {:game_updated, _}
      assert GameServer.exists?(game_state.id)
      assert GameServer.get_game(game_state.id).game_status == :lobby
      assert GameServer.get_game(game_state.id).owner.id == game_state.owner.id
    end

    test "REQ-03: rejects non-member leave, give_up, and guess without saving or broadcasting", %{
      game_state: game_state
    } do
      player1 = insert(:player)
      player2 = insert(:player)
      outsider = insert(:player)

      assert {:ok, :joined} = GameServer.join_room(game_state.id, player1.id)
      assert {:ok, :joined} = GameServer.join_room(game_state.id, player2.id)
      flush_messages()

      assert {:error, :not_a_participant} = GameServer.leave_game(game_state.id, outsider.id)
      assert {:error, :not_a_participant} = GameServer.give_up_game(game_state.id, outsider.id)
      assert {:error, :not_a_participant} = GameServer.guess(game_state.id, outsider.id, "a")
      refute_receive {:game_updated, _}

      assert :ok = GameServer.start_game(game_state.id, game_state.owner.id)
      flush_messages()

      assert {:error, :not_a_participant} = GameServer.leave_game(game_state.id, outsider.id)
      assert {:error, :not_a_participant} = GameServer.give_up_game(game_state.id, outsider.id)
      assert {:error, :not_a_participant} = GameServer.guess(game_state.id, outsider.id, "a")
      refute_receive {:game_updated, _}
    end

    test "REQ-03: rejects stale owner commands immediately after transfer_ownership/3", %{
      game_state: game_state
    } do
      player1 = insert(:player)
      player2 = insert(:player)
      old_owner_id = game_state.owner.id

      assert {:ok, :joined} = GameServer.join_room(game_state.id, player1.id)
      assert {:ok, :joined} = GameServer.join_room(game_state.id, player2.id)

      assert :ok = GameServer.transfer_ownership(game_state.id, old_owner_id, player1.id)
      flush_messages()

      assert {:error, :unauthorized} =
               GameServer.update_settings(game_state.id, old_owner_id, %{name: "Stale"})

      assert {:error, :unauthorized} = GameServer.start_game(game_state.id, old_owner_id)

      assert {:error, :unauthorized} =
               GameServer.transfer_ownership(game_state.id, old_owner_id, player2.id)

      assert {:error, :unauthorized} = GameServer.restart_game(game_state.id, old_owner_id)
      assert {:error, :unauthorized} = GameServer.archive_game(game_state.id, old_owner_id)
      refute_receive {:game_updated, _}

      assert :ok = GameServer.start_game(game_state.id, player1.id)
      assert_receive {:game_updated, %{game_status: :playing}}
    end
  end
end
