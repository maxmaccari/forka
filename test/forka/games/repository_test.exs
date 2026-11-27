defmodule Forka.Games.RepositoryTest do
  use Forka.DataCase, async: true

  alias Forka.Games.Core
  alias Forka.Games.Core.GameState
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.GamePlayer
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.Word
  alias Forka.Games.Schemas.WordOptions

  test "the game player changeset takes turn position from the game state" do
    player = %GamePlayer{player_id: Ecto.UUID.generate(), position: 1}
    changeset = GamePlayer.changeset(player, %{position: 5})

    assert get_field(changeset, :position) == 1
  end

  @tag audit_f05: true
  test "F-05 reloading a saved game restores the exact turn order" do
    game = insert(:game)
    player_one = to_games_player(insert(:player))
    player_two = to_games_player(insert(:player))
    {:ok, state} = Repository.get_game_state(game.id)
    {:ok, state} = Core.join_game(state, player_one)
    {:ok, state} = Core.join_game(state, player_two)
    {:ok, state} = Repository.save_game_state(state)

    player_one_state = Enum.find(Map.values(state.game_players), &(&1.player_id == player_one.id))
    player_two_state = Enum.find(Map.values(state.game_players), &(&1.player_id == player_two.id))

    state =
      %{state | game_players: %{0 => player_two_state, 1 => player_one_state}}
      |> Core.set_words([
        Word.new("cat", "Animals"),
        Word.new("dog", "Animals"),
        Word.new("fox", "Animals"),
        Word.new("owl", "Animals")
      ])

    {:ok, state} = Core.start_game(state, state.owner.id)
    assert {:ok, _state} = Repository.save_game_state(state)
    {:ok, reloaded} = Repository.get_game_state(game.id)

    assert reloaded.game_players[0].position == 0
    assert reloaded.game_players[1].position == 1
    assert reloaded.game_players[0].player_id == player_two.id
    assert reloaded.game_players[1].player_id == player_one.id
    assert Core.get_current_player(reloaded).id == player_two.id
  end

  describe "get_random_words/2" do
    test "returns the specified number of random words" do
      # Create categories and words
      category1 = insert(:category, name: "Animals", language: "en")
      category2 = insert(:category, name: "Colors", language: "en")
      category3 = insert(:category, name: "Animais", language: "pt")

      insert(:word, text: "dog", hint: "Barks", category: category1)
      insert(:word, text: "cat", hint: "Meows", category: category1)
      insert(:word, text: "blue", hint: "Color of the sky", category: category2)
      insert(:word, text: "red", hint: "Color of blood", category: category2)
      insert(:word, text: "cachorro", hint: "Late", category: category3)

      # Test default count, it will load words from the the default language (en)
      words = Repository.get_random_words()
      assert length(words) == 4
      assert %{text: _, hint: _, category: _, language: _} = List.first(words)

      # Test with specific count
      words = Repository.get_random_words(2)
      assert length(words) == 2

      assert Enum.all?(words, fn word ->
               is_map(word) and Map.has_key?(word, :text) and Map.has_key?(word, :category)
             end)

      # Test with language filter
      word_options = %WordOptions{language: "en"}
      en_words = Repository.get_random_words(5, word_options)
      assert length(en_words) == 4
      assert Enum.all?(en_words, fn word -> word.language == "en" end)

      word_options = %WordOptions{language: "pt"}
      pt_words = Repository.get_random_words(5, word_options)
      assert length(pt_words) == 1
      assert Enum.all?(pt_words, fn word -> word.language == "pt" end)

      # Test with category_ids filter
      word_options = %WordOptions{category_ids: [category1.id]}
      category_words = Repository.get_random_words(5, word_options)
      assert length(category_words) == 2
      assert Enum.all?(category_words, fn word -> word.category == "Animals" end)
    end

    test "REQ-01 & EDGE-01: returns distinct playable Word structs and ignores accent/case duplicates and empty text" do
      cat_a = insert(:category, name: "Comida", language: "pt")
      cat_b = insert(:category, name: "Bebidas", language: "pt")

      insert(:word, text: "café", category: cat_a)
      insert(:word, text: "cafe", category: cat_a)
      insert(:word, text: "CAFÉ", category: cat_b)
      insert(:word, text: "pão", category: cat_a)
      insert(:word, text: "suco", category: cat_b)
      insert(:word, text: "bolo", category: cat_a)
      Repo.insert!(%Forka.Words.Word{text: "   ", category_id: cat_a.id})
      Repo.insert!(%Forka.Words.Word{text: "---", category_id: cat_b.id})

      opts = %WordOptions{language: "pt", category_ids: [cat_a.id, cat_b.id]}
      words = Repository.get_random_words(4, opts)

      assert length(words) == 4
      assert Enum.all?(words, &Word.playable?/1)

      keys = words |> Enum.map(&Word.normalized_key/1) |> MapSet.new()
      assert keys == MapSet.new(["cafe", "pao", "suco", "bolo"])
    end
  end

  describe "count_available_words/1" do
    test "EDGE-03: normalizes legacy keyword word_options for get_random_words/2 and count_available_words/1" do
      cat_pt = insert(:category, name: "Animais", language: "pt")
      insert(:word, text: "gato", category: cat_pt)
      insert(:word, text: "pato", category: cat_pt)

      assert Repository.count_available_words(language: "pt") == 2
      assert length(Repository.get_random_words(2, language: "pt")) == 2
    end
  end

  describe "get_player/1" do
    test "returns the player with given id" do
      %{id: id, username: username} = player = insert(:player)
      assert %Player{id: ^id, username: ^username} = Repository.get_player(player.id)
    end

    test "returns nil when player does not exist" do
      assert Repository.get_player(Ecto.UUID.generate()) == nil
    end
  end

  describe "insert_game/1" do
    @valid_attrs %{
      name: "Test Game",
      max_players: 4
    }

    test "successfully inserts a game with valid parameters" do
      player = insert(:player)

      assert {:ok, inserted_game} = Repository.insert_game(player.id, @valid_attrs)
      assert inserted_game.name == "Test Game"
      assert inserted_game.max_players == 4
      assert inserted_game.status == :lobby
      assert inserted_game.owner_id == player.id
    end

    test "returns error changeset with invalid parameters" do
      player = insert(:player)

      # Test with invalid name (nil)
      invalid_attrs = %{@valid_attrs | name: nil}
      assert {:error, changeset} = Repository.insert_game(player.id, invalid_attrs)
      assert "can't be blank" in errors_on(changeset).name

      # Test with invalid max_players (negative)
      invalid_attrs = %{@valid_attrs | max_players: -1}
      assert {:error, changeset} = Repository.insert_game(player.id, invalid_attrs)
      assert errors_on(changeset).max_players

      # Test with invalid word_options
      invalid_attrs = Map.put(@valid_attrs, :word_options, %{language: nil})
      assert {:error, changeset} = Repository.insert_game(player.id, invalid_attrs)
      assert %{word_options: %{language: ["can't be blank"]}} = errors_on(changeset)

      # Test with non-existent player ID
      assert {:error, changeset} = Repository.insert_game(Ecto.UUID.generate(), @valid_attrs)
      assert errors_on(changeset).owner_id
    end

    test "ignores non-permitted parameters" do
      player = insert(:player)

      # Include non-permitted parameters
      attrs_with_extra =
        Map.merge(@valid_attrs, %{
          status: :playing,
          current_game_word_index: 5,
          current_game_player_index: 2,
          non_existent_field: "should be ignored"
        })

      assert {:ok, inserted_game} = Repository.insert_game(player.id, attrs_with_extra)

      # Verify that non-permitted parameters were ignored
      assert inserted_game.name == "Test Game"
      assert inserted_game.max_players == 4
      # Default value, not the one we tried to set
      assert inserted_game.status == :lobby
      assert inserted_game.current_game_word_index == nil
      assert inserted_game.current_game_player_index == nil
      refute Map.has_key?(inserted_game, :non_existent_field)
    end
  end

  describe "get_game_state/1" do
    test "returns a game state when the game exists" do
      game = insert(:game)

      assert {:ok, %GameState{} = game_state} = Repository.get_game_state(game.id)
      assert game_state.id == game.id
      assert game_state.name == game.name
      assert game_state.max_players == game.max_players
      assert game_state.status == :lobby
    end

    test "returns error when game does not exist" do
      assert {:error, :not_found} = Repository.get_game_state(UUID.uuid4())
    end
  end

  describe "update_game_state/1" do
    test "successfully updates a game" do
      # Create a game first
      game = insert(:game)
      {:ok, game_state} = Repository.get_game_state(game.id)

      # Modify the game state
      updated_game_state = %{
        game_state
        | name: "Updated Game Name",
          max_players: 6,
          word_options: %{
            game_state.word_options
            | language: "pt",
              category_ids: ["category1", "category2"]
          }
      }

      # Save the updated game state
      assert {:ok, saved_game_state} = Repository.save_game_state(updated_game_state)
      assert saved_game_state.id == game_state.id
      assert saved_game_state.name == "Updated Game Name"
      assert saved_game_state.max_players == 6
      assert saved_game_state.word_options.language == "pt"
      assert saved_game_state.word_options.category_ids == ["category1", "category2"]

      # Verify the change was persisted
      {:ok, reloaded_game_state} = Repository.get_game_state(game.id)
      assert reloaded_game_state.name == "Updated Game Name"
      assert reloaded_game_state.max_players == 6
      assert reloaded_game_state.word_options.language == "pt"
      assert reloaded_game_state.word_options.category_ids == ["category1", "category2"]
    end

    test "returns error changeset when updating with invalid params" do
      # Create a game first
      game = insert(:game)
      {:ok, game_state} = Repository.get_game_state(game.id)

      # Modify the game state with invalid data
      invalid_game_state = %{
        game_state
        | # Empty name is invalid
          name: "",
          # Max players > 6 is invalid
          max_players: 10
      }

      # Attempt to save the invalid game state
      assert {:error, changeset} = Repository.save_game_state(invalid_game_state)

      # Verify the changeset contains the expected errors
      assert "can't be blank" in errors_on(changeset).name
      assert "must be between 2 and 6 players" in errors_on(changeset).max_players

      # Verify the original game was not changed
      {:ok, unchanged_game_state} = Repository.get_game_state(game.id)
      assert unchanged_game_state.name == game_state.name
      assert unchanged_game_state.max_players == game_state.max_players
    end

    test "R-03: rejects saving a game state with an alive player at zero lives" do
      owner = to_games_player(insert(:player))
      player2 = to_games_player(insert(:player))
      game = insert(:game, owner_id: owner.id)

      {:ok, game_state} = Repository.get_game_state(game.id)
      {:ok, game_state} = Core.join_game(game_state, owner)
      {:ok, game_state} = Core.join_game(game_state, player2)
      {:ok, saved_state} = Repository.save_game_state(game_state)

      corrupt_players =
        Map.update!(saved_state.game_players, 0, fn gp -> %{gp | status: :alive, lives: 0} end)

      assert {:error, changeset} =
               Repository.save_game_state(%{saved_state | game_players: corrupt_players})

      assert %{lives: ["must be greater than 0 while player is alive"]} in errors_on(changeset).game_players
    end

    test "saves a complete game state with players, words, and guesses in playing state" do
      # Create a game with an owner
      owner = to_games_player(insert(:player))
      game = insert(:game, owner_id: owner.id)

      # Add players to the game
      player1 = to_games_player(insert(:player))
      player2 = to_games_player(insert(:player))
      player3 = to_games_player(insert(:player))

      # Get the initial game state
      {:ok, game_state} = Repository.get_game_state(game.id)

      # Add players to the game using Game module
      {:ok, game_state} = Core.join_game(game_state, player1)
      {:ok, game_state} = Core.join_game(game_state, player2)
      {:ok, game_state} = Core.join_game(game_state, player3)

      # Add words to the game
      words = [
        %Word{
          text: "apple",
          hint: "A fruit",
          category: "Food",
          language: "en"
        },
        %Word{
          text: "banana",
          hint: "Yellow fruit",
          category: "Food",
          language: "en"
        },
        %Word{
          text: "orange",
          hint: "Citrus fruit",
          category: "Food",
          language: "en"
        },
        %Word{
          text: "grape",
          hint: "Small fruit",
          category: "Food",
          language: "en"
        },
        %Word{
          text: "melon",
          hint: "Sweet fruit",
          category: "Food",
          language: "en"
        },
        %Word{
          text: "peach",
          hint: "Fuzzy fruit",
          category: "Food",
          language: "en"
        }
      ]

      # Set words using Game module
      game_state = Core.set_words(game_state, words)

      # Start the game
      {:ok, game_state} = Core.start_game(game_state, owner.id)

      # Make some guesses
      {:ok, game_state} = Core.guess(game_state, player1.id, "a")
      {:ok, game_state} = Core.guess(game_state, player1.id, "p")
      {:ok, game_state} = Core.guess(game_state, player1.id, "z")

      {:ok, game_state} = Core.guess(game_state, player2.id, "l")
      {:ok, game_state} = Core.guess(game_state, player2.id, "e")

      # Save the complete game state
      assert {:ok, saved_game_state} = Repository.save_game_state(game_state)

      # Verify the game state was saved correctly
      assert saved_game_state.status == :playing
      assert saved_game_state.current_game_word_index == 1
      assert saved_game_state.current_game_player_index == 1

      # Verify players were saved
      assert map_size(saved_game_state.game_players) == 3

      # Verify words were saved
      assert map_size(saved_game_state.game_words) == 6
      assert saved_game_state.game_words[0].word.text == "apple"
      assert saved_game_state.game_words[1].word.text == "banana"
      assert saved_game_state.game_words[2].word.text == "orange"

      # Verify guesses were saved
      assert length(saved_game_state.game_words[0].guesses) == 5
      assert Enum.any?(saved_game_state.game_words[0].guesses, &(&1.letter == "a"))
      assert Enum.any?(saved_game_state.game_words[0].guesses, &(&1.letter == "p"))
      assert Enum.any?(saved_game_state.game_words[0].guesses, &(&1.letter == "z"))
      assert Enum.any?(saved_game_state.game_words[0].guesses, &(&1.letter == "l"))
      assert Enum.any?(saved_game_state.game_words[0].guesses, &(&1.letter == "e"))

      assert saved_game_state.game_words[0].finished_by_id == player2.id

      # Verify player lives (player who guessed incorrectly should have lost a life)
      incorrect_player =
        Enum.find(Map.values(saved_game_state.game_players), &(&1.player_id == player1.id))

      assert incorrect_player.lives < 6

      # Reload the game state to verify persistence
      {:ok, reloaded_game_state} = Repository.get_game_state(game.id)
      assert reloaded_game_state.status == :playing
      assert map_size(reloaded_game_state.game_players) == 3
      assert map_size(reloaded_game_state.game_words) == 6
      assert length(reloaded_game_state.game_words[0].guesses) == 5

      assert reloaded_game_state.current_game_word_index == 1
      assert reloaded_game_state.current_game_player_index == 1
    end

    test "rejects updates to fields when game is archived" do
      player = insert(:player)
      archived_game = insert(:game, owner: player, status: :archived)

      {:ok, archived_state} = Repository.get_game_state(archived_game.id)

      updated_archived_state = %{
        archived_state
        | name: "New Archived Name",
          max_players: 6,
          current_game_word_index: 3,
          current_game_player_index: 2
      }

      # Should reject all changes in archived state
      assert {:error, _reason} = Repository.save_game_state(updated_archived_state)
    end

    test "allows ownership transfer to another player" do
      owner = insert(:player) |> to_games_player()
      player2 = insert(:player) |> to_games_player()
      player3 = insert(:player) |> to_games_player()

      game = insert(:game, owner: owner, status: :lobby)

      # Get the game state
      {:ok, game_state} = Repository.get_game_state(game.id)

      # Add players to the game
      {:ok, game_state} = Core.join_game(game_state, player2)
      {:ok, game_state} = Core.join_game(game_state, player3)

      # Transfer ownership to player2
      {:ok, updated_game_state} =
        Core.transfer_ownership_to_player(game_state, owner.id, player2.id)

      # Save the updated game state
      assert {:ok, saved_game_state} = Repository.save_game_state(updated_game_state)

      # Verify ownership was transferred
      assert saved_game_state.owner.id == player2.id

      # Reload the game state to verify persistence
      {:ok, reloaded_game_state} = Repository.get_game_state(game.id)
      assert reloaded_game_state.owner.id == player2.id

      # Test ownership transfer in playing state
      playing_game_state =
        Core.set_words(saved_game_state, [
          Word.new("apple", "fruits"),
          Word.new("banana", "fruits"),
          Word.new("cherry", "fruits"),
          Word.new("mango", "fruits")
        ])

      {:ok, playing_game_state} = Core.start_game(playing_game_state, player2.id)

      # Transfer ownership to player3 while game is in progress
      {:ok, updated_playing_state} =
        Core.transfer_ownership_to_player(playing_game_state, player2.id, player3.id)

      assert {:ok, saved_playing_state} = Repository.save_game_state(updated_playing_state)

      # Verify ownership was transferred in playing state
      assert saved_playing_state.owner.id == player3.id
      assert saved_playing_state.status == :playing
    end

    test "OWN-01: allows saving an archived game with nil owner after owner deletion while still requiring owner_id for non-archived games" do
      owner = insert(:player, username: "lia")
      game = insert(:game, owner: owner, status: :lobby)

      Repo.delete!(owner)
      {:ok, ownerless_state} = Repository.get_game_state(game.id)
      assert ownerless_state.owner == nil

      # Non-archived save with nil owner still fails validation
      assert {:error, non_archived_cs} =
               Repository.save_game_state(%{ownerless_state | name: "Still Lobby"})

      assert "can't be blank" in errors_on(non_archived_cs).owner_id

      # Archiving an ownerless game succeeds so empty rooms can be closed cleanly
      {:ok, archived_state} = Core.archive_game(ownerless_state)
      assert {:ok, saved} = Repository.save_game_state(archived_state)
      assert saved.status == :archived
      assert saved.owner == nil
    end
  end

  describe "save_game_state!/1" do
    test "successfully saves game state and returns the updated state" do
      owner = insert(:player) |> to_games_player()
      game = insert(:game, owner: owner, status: :lobby)

      {:ok, game_state} = Repository.get_game_state(game.id)

      # Make a change to the game state
      updated_game_state = %{game_state | name: "Updated Game Name"}

      # Save using save_game_state!
      result = Repository.save_game_state!(updated_game_state)

      # Verify it returns the updated game state
      assert result.name == "Updated Game Name"
      assert result.id == game.id

      # Verify it was actually persisted
      {:ok, reloaded_state} = Repository.get_game_state(game.id)
      assert reloaded_state.name == "Updated Game Name"
    end

    test "raises an exception when game state cannot be saved" do
      owner = insert(:player) |> to_games_player()
      game = insert(:game, owner: owner, status: :lobby)

      {:ok, game_state} = Repository.get_game_state(game.id)

      # Create an invalid game state (nil id)
      invalid_game_state = %{game_state | status: nil}

      # Should raise an exception
      assert_raise Ecto.InvalidChangesetError, fn ->
        Repository.save_game_state!(invalid_game_state)
      end
    end
  end

  describe "backoffice subscriptions" do
    test "broadcasts backpex:created event when a game is inserted" do
      owner = insert(:player)

      # Subscribe to the backoffice topic
      Phoenix.PubSub.subscribe(Forka.PubSub, "games")

      # Insert a new game
      {:ok, game} = Repository.insert_game(owner.id, %{name: "Test Game", max_players: 4})
      game_id = game.id

      # Assert we receive the broadcast
      assert_receive {"backpex:created", %{id: ^game_id} = broadcasted_game}
      assert broadcasted_game.name == "Test Game"
    end

    test "broadcasts backpex:updated when a game state is saved" do
      owner = insert(:player) |> to_games_player()
      game = insert(:game, owner: owner, status: :lobby)
      game_id = game.id

      {:ok, game_state} = Repository.get_game_state(game.id)

      # Subscribe to the backoffice topic
      Phoenix.PubSub.subscribe(Forka.PubSub, "games")

      # Update the game state
      updated_game_state = %{game_state | name: "Updated Game Name"}
      {:ok, _saved_state} = Repository.save_game_state(updated_game_state)

      # Assert we receive the broadcast
      assert_receive {"backpex:updated", %{id: ^game_id} = broadcasted_game}
      assert broadcasted_game.name == "Updated Game Name"
    end
  end

  describe "existing_player_ids/1" do
    test "OWN-01: returns only player IDs that still exist in persistence" do
      kept = insert(:player)
      deleted = insert(:player)
      missing_id = Ecto.UUID.generate()

      Repo.delete!(deleted)

      assert Repository.existing_player_ids([]) == []

      result = Repository.existing_player_ids([kept.id, deleted.id, missing_id, kept.id])
      assert result == [kept.id]
    end
  end

  describe "reconcile_game_state/2" do
    test "F-01: locks and reconciles an ownerless game atomically, and treats archived or missing games cleanly" do
      owner = insert(:player, username: "lia")
      {:ok, game} = Repository.insert_game(owner.id, %{name: "Orfa", max_players: 4})
      Repo.delete!(owner)

      assert {:ok, :reconciled, prev, saved} =
               Repository.reconcile_game_state(game.id, &Core.reconcile_missing_players/2)

      assert prev.status == :lobby
      assert saved.status == :archived
      assert saved.owner == nil

      # Second reconciliation sees already-archived row and returns :unchanged without raising
      assert {:ok, :unchanged, archived} =
               Repository.reconcile_game_state(game.id, &Core.reconcile_missing_players/2)

      assert archived.status == :archived

      assert {:error, :not_found} =
               Repository.reconcile_game_state(UUID.uuid4(), &Core.reconcile_missing_players/2)
    end
  end

  describe "F-03: persisted seat position turn resolution" do
    test "F-03: deleting the active turn player in the last seat wraps turn to the next alive seat on reload" do
      owner = insert(:player, username: "lia")
      p1 = insert(:player, username: "bruno")
      p2 = insert(:player, username: "caio")

      words =
        for text <- ~w(alfa bravo charlie delta echo foxtrot),
            do: Word.new(text, "Geral")

      {:ok, game} = Repository.insert_game(owner.id, %{name: "Wrap Turno", max_players: 4})
      {:ok, state} = Repository.get_game_state(game.id)
      {:ok, state} = Core.join_game(state, Repository.get_player(p1.id))
      {:ok, state} = Core.join_game(state, Repository.get_player(p2.id))
      {:ok, playing} = state |> Core.set_words(words) |> Core.start_game(owner.id)

      # Seat 2 (p2) is up when p2 is deleted from persistence
      {:ok, _saved} = Repository.save_game_state(%{playing | current_game_player_index: 2})
      Repo.delete!(p2)

      {:ok, reloaded} = Repository.get_game_state(game.id)
      assert reloaded.current_game_player_index == 0
      assert Core.get_current_player(reloaded).id == owner.id
    end
  end

  defp to_games_player(%Forka.Players.Player{} = player) do
    %Forka.Games.Schemas.Player{
      id: player.id,
      username: player.username
    }
  end
end
