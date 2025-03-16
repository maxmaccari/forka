defmodule Forka.Games.WordsRepositoryTest do
  use Forka.DataCase

  alias Forka.Games.WordsRepository

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
      words = WordsRepository.get_random_words()
      assert length(words) == 5
      assert %{text: _, hint: _, category: _, language: _} = List.first(words)

      # Test with specific count
      words = WordsRepository.get_random_words(2)
      assert length(words) == 2

      assert Enum.all?(words, fn word ->
               is_map(word) and Map.has_key?(word, :text) and Map.has_key?(word, :category)
             end)

      # Test with language filter
      en_words = WordsRepository.get_random_words(5, language: "en")
      assert length(en_words) == 4
      assert Enum.all?(en_words, fn word -> word.language == "en" end)

      pt_words = WordsRepository.get_random_words(5, language: "pt")
      assert length(pt_words) == 1
      assert Enum.all?(pt_words, fn word -> word.language == "pt" end)

      # Test with category_ids filter
      category_words = WordsRepository.get_random_words(5, category_ids: [category1.id])
      assert length(category_words) == 2
      assert Enum.all?(category_words, fn word -> word.category == "Animals" end)
    end
  end
end
