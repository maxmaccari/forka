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
end
