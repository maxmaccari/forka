defmodule Forka.Games.RepositoryTest do
  alias Forka.Games.Game.GameState
  use Forka.DataCase

  alias Forka.Games.Repository
  alias Forka.Games.Schemas.Player

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

      # Test default count
      words = Repository.get_random_words()
      assert length(words) == 5
      assert %{text: _, hint: _, category: _, language: _} = List.first(words)

      # Test with specific count
      words = Repository.get_random_words(2)
      assert length(words) == 2

      assert Enum.all?(words, fn word ->
               is_map(word) and Map.has_key?(word, :text) and Map.has_key?(word, :category)
             end)

      # Test with language filter
      en_words = Repository.get_random_words(5, language: "en") |> dbg()
      assert length(en_words) == 4
      assert Enum.all?(en_words, fn word -> word.language == "en" end)

      pt_words = Repository.get_random_words(5, language: "pt")
      assert length(pt_words) == 1
      assert Enum.all?(pt_words, fn word -> word.language == "pt" end)

      # Test with category_ids filter
      category_words = Repository.get_random_words(5, category_ids: [category1.id])
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
      {:ok, game_state} = Forka.Games.Game.join_game(game_state, player1)
      {:ok, game_state} = Forka.Games.Game.join_game(game_state, player2)
      {:ok, game_state} = Forka.Games.Game.join_game(game_state, player3)

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
      game_state = Forka.Games.Game.set_words(game_state, words)

      # Start the game
      {:ok, game_state} = Forka.Games.Game.start_game(game_state)

      # Make some guesses
      {:ok, game_state} = Forka.Games.Game.guess(game_state, player1.id, "a")
      {:ok, game_state} = Forka.Games.Game.guess(game_state, player1.id, "p")
      {:ok, game_state} = Forka.Games.Game.guess(game_state, player1.id, "z")

      {:ok, game_state} = Forka.Games.Game.guess(game_state, player2.id, "l")
      {:ok, game_state} = Forka.Games.Game.guess(game_state, player2.id, "e")

      # Save the complete game state
      assert {:ok, saved_game_state} = Repository.save_game_state(game_state)

      # Verify the game state was saved correctly
      assert saved_game_state.status == :playing
      assert saved_game_state.current_game_word_index == 1
      assert saved_game_state.current_game_player_index == 1

      # Verify players were saved
      assert map_size(saved_game_state.players) == 3

      # Verify words were saved
      assert map_size(saved_game_state.words) == 3
      assert saved_game_state.words[0].word.text == "apple"
      assert saved_game_state.words[1].word.text == "banana"
      assert saved_game_state.words[2].word.text == "orange"

      # Verify guesses were saved
      assert length(saved_game_state.words[0].guesses) == 5
      assert Enum.any?(saved_game_state.words[0].guesses, &(&1.letter == "a"))
      assert Enum.any?(saved_game_state.words[0].guesses, &(&1.letter == "p"))
      assert Enum.any?(saved_game_state.words[0].guesses, &(&1.letter == "z"))
      assert Enum.any?(saved_game_state.words[0].guesses, &(&1.letter == "l"))
      assert Enum.any?(saved_game_state.words[0].guesses, &(&1.letter == "e"))

      assert saved_game_state.words[0].finished_by_id == player2.id

      # Verify player lives (player who guessed incorrectly should have lost a life)
      incorrect_player =
        Enum.find(Map.values(saved_game_state.players), &(&1.player_id == player1.id))

      assert incorrect_player.lives < 6

      # Reload the game state to verify persistence
      {:ok, reloaded_game_state} = Repository.get_game_state(game.id)
      assert reloaded_game_state.status == :playing
      assert map_size(reloaded_game_state.players) == 3
      assert map_size(reloaded_game_state.words) == 3
      assert length(reloaded_game_state.words[0].guesses) == 5

      assert reloaded_game_state.current_game_word_index == 1
      assert reloaded_game_state.current_game_player_index == 1
    end
  end

  defp to_games_player(%Forka.Players.Player{} = player) do
    %Forka.Games.Schemas.Player{
      id: player.id,
      username: player.username
    }
  end
end
