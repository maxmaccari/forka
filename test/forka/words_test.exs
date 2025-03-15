defmodule Forka.WordsTest do
  use Forka.DataCase

  alias Forka.Words

  describe "categories" do
    test "list_categories/0 returns all categories" do
      category = insert(:category)
      assert Words.list_categories() == [category]
    end

    test "list_categories/1 returns all categories by language" do
      pt_category = insert(:category, language: "pt")
      en_category = insert(:category, language: "en")

      assert Words.list_categories(language: "pt") == [pt_category]
      assert Words.list_categories(language: "en") == [en_category]
      assert Words.list_categories(language: "EN") == [en_category]
    end
  end

  describe "import_words/1" do
    alias Forka.Words.Word

    test "imports words from a list of maps with string keys" do
      words_data = [
        %{
          "category" => "Animal",
          "name" => "horse",
          "hint" => "Used as transportation"
        },
        %{
          "category" => "Animal",
          "name" => "thrush",
          "hint" => "Sings beautifully"
        },
        %{
          "category" => "Vehicle",
          "name" => "airplane",
          "hint" => "Flies"
        }
      ]

      assert {:ok, imported_words} = Words.import_words(words_data)
      assert length(imported_words) == 3

      # Check that categories were created
      categories = Words.list_categories()
      assert Enum.any?(categories, &(&1.name == "Animal"))
      assert Enum.any?(categories, &(&1.name == "Vehicle"))

      # Check that words were created with correct attributes
      animal_category = Enum.find(categories, &(&1.name == "Animal"))
      vehicle_category = Enum.find(categories, &(&1.name == "Vehicle"))

      assert Repo.exists?(
               from w in Word, where: w.text == "horse" and w.category_id == ^animal_category.id
             )

      assert Repo.exists?(
               from w in Word, where: w.text == "thrush" and w.category_id == ^animal_category.id
             )

      assert Repo.exists?(
               from w in Word,
                 where: w.text == "airplane" and w.category_id == ^vehicle_category.id
             )
    end

    test "imports words from a list of maps with atom keys" do
      words_data = [
        %{
          category: "Fruit",
          name: "banana",
          hint: "Yellow"
        },
        %{
          category: "Fruit",
          name: "apple",
          hint: "Red"
        }
      ]

      assert {:ok, imported_words} = Words.import_words(words_data)
      assert length(imported_words) == 2

      # Check that category was created
      categories = Words.list_categories()
      assert Enum.any?(categories, &(&1.name == "Fruit"))

      # Check that words were created with correct attributes
      fruit_category = Enum.find(categories, &(&1.name == "Fruit"))

      assert Repo.exists?(
               from w in Word, where: w.text == "banana" and w.category_id == ^fruit_category.id
             )

      assert Repo.exists?(
               from w in Word, where: w.text == "apple" and w.category_id == ^fruit_category.id
             )
    end

    test "skips words that already exist in a category" do
      # Create a category and word first
      category = insert(:category, name: "Color")
      insert(:word, text: "blue", category: category)

      words_data = [
        %{
          "category" => "Color",
          "name" => "blue",
          "hint" => "Color of the sky"
        },
        %{
          "category" => "Color",
          "name" => "green",
          "hint" => "Color of plants"
        }
      ]

      assert {:ok, imported_words} = Words.import_words(words_data)
      assert length(imported_words) == 1

      # Only the new word should be added
      assert Enum.any?(imported_words, &(&1.text == "green"))
      refute Enum.any?(imported_words, &(&1.text == "blue"))
    end

    test "handles case insensitivity correctly" do
      # Create a category and word first
      category = insert(:category, name: "Color")
      insert(:word, text: "blue", category: category)

      words_data = [
        %{
          "category" => "Color",
          # Different case
          "name" => "BLUE",
          "hint" => "Color of the sky"
        },
        %{
          # Different case for category
          "category" => "color",
          "name" => "green",
          "hint" => "Color of plants"
        }
      ]

      assert {:ok, imported_words} = Words.import_words(words_data)
      assert length(imported_words) == 1

      # Only the new word should be added
      assert Enum.any?(imported_words, &(&1.text == "green"))
      refute Enum.any?(imported_words, &(&1.text == "blue"))
    end
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

      # Test default count
      words = Words.get_random_words()
      assert length(words) == 5
      assert %{text: _, hint: _, category: _, language: _} = List.first(words)

      # Test with specific count
      words = Words.get_random_words(2)
      assert length(words) == 2

      assert Enum.all?(words, fn word ->
               is_map(word) and Map.has_key?(word, :text) and Map.has_key?(word, :category)
             end)

      # Test with language filter
      en_words = Words.get_random_words(5, language: "en")
      assert length(en_words) == 4
      assert Enum.all?(en_words, fn word -> word.language == "en" end)

      pt_words = Words.get_random_words(5, language: "pt")
      assert length(pt_words) == 1
      assert Enum.all?(pt_words, fn word -> word.language == "pt" end)

      # Test with category_ids filter
      category_words = Words.get_random_words(5, category_ids: [category1.id])
      assert length(category_words) == 2
      assert Enum.all?(category_words, fn word -> word.category == "Animals" end)
    end
  end
end
