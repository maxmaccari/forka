defmodule Forka.Games.RepositoryTest do
  use Forka.DataCase, async: true

  alias Forka.Games.Core
  alias Forka.Games.Core.GameState
  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Player
  alias Forka.Games.Schemas.WordOptions

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
        %Forka.Games.Schemas.Word{
          text: "apple",
          hint: "A fruit",
          category: "Food",
          language: "en"
        },
        %Forka.Games.Schemas.Word{
          text: "banana",
          hint: "Yellow fruit",
          category: "Food",
          language: "en"
        },
        %Forka.Games.Schemas.Word{
          text: "orange",
          hint: "Citrus fruit",
          category: "Food",
          language: "en"
        }
      ]

      # Set words using Game module
      game_state = Core.set_words(game_state, words)

      # Start the game
      {:ok, game_state} = Core.start_game(game_state)

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
      assert map_size(saved_game_state.game_words) == 3
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
      assert map_size(reloaded_game_state.game_words) == 3
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
        Core.transfer_ownership_to_player(game_state, player2.id)

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
          Forka.Games.Schemas.Word.new("apple", "fruits"),
          Forka.Games.Schemas.Word.new("banana", "fruits")
        ])

      {:ok, playing_game_state} = Core.start_game(playing_game_state)

      # Transfer ownership to player3 while game is in progress
      {:ok, updated_playing_state} =
        Core.transfer_ownership_to_player(playing_game_state, player3.id)

      assert {:ok, saved_playing_state} = Repository.save_game_state(updated_playing_state)

      # Verify ownership was transferred in playing state
      assert saved_playing_state.owner.id == player3.id
      assert saved_playing_state.status == :playing
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

  defp to_games_player(%Forka.Players.Player{} = player) do
    %Forka.Games.Schemas.Player{
      id: player.id,
      username: player.username
    }
  end
end
