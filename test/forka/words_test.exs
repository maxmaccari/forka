defmodule Forka.WordsTest do
  use Forka.DataCase

  alias Forka.Words
  alias Forka.WordText

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

    test "AC-01: list_categories_by_ids/1 returns matching categories sorted by name and handles empty list" do
      music = insert(:category, name: "Música", language: "pt")
      games = insert(:category, name: "Jogos", language: "pt")
      _other = insert(:category, name: "Cinema", language: "pt")

      assert Words.list_categories_by_ids([]) == []

      result = Words.list_categories_by_ids([music.id, games.id, music.id])
      assert Enum.map(result, & &1.id) == [games.id, music.id]
      assert Enum.map(result, & &1.name) == ["Jogos", "Música"]
    end

    test "AC-01: list_categories/1 orders results alphabetically by name" do
      z = insert(:category, name: "Zoologia", language: "pt")
      a = insert(:category, name: "Animais", language: "pt")
      m = insert(:category, name: "Música", language: "pt")
      _en = insert(:category, name: "Animals", language: "en")

      result = Words.list_categories(language: "pt")
      assert Enum.map(result, & &1.id) == [a.id, m.id, z.id]
    end

    test "AC-01: list_category_ids_for_language/2 returns only existing IDs belonging to that language" do
      pt_a = insert(:category, name: "Animais", language: "pt")
      pt_b = insert(:category, name: "Filmes", language: "pt")
      en_a = insert(:category, name: "Animals", language: "en")
      stale_id = Ecto.UUID.generate()

      assert Words.list_category_ids_for_language("pt", []) == []

      assert MapSet.new(
               Words.list_category_ids_for_language("pt", [pt_a.id, pt_b.id, en_a.id, stale_id])
             ) == MapSet.new([pt_a.id, pt_b.id])

      assert Words.list_category_ids_for_language("en", [pt_a.id, en_a.id]) == [en_a.id]
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

  describe "count_distinct_playable_words/1 and sample_distinct_playable_words/2" do
    test "REQ-01 & EDGE-01: counts only distinct playable words by language and categories" do
      pt_food = insert(:category, name: "Comida", language: "pt")
      pt_drinks = insert(:category, name: "Bebidas", language: "pt")
      en_food = insert(:category, name: "Food", language: "en")

      # Accent/case duplicates and cross-category duplicates collapse to 1 each
      insert(:word, text: "café", category: pt_food)
      insert(:word, text: "cafe", category: pt_food)
      insert(:word, text: "CAFÉ", category: pt_drinks)
      insert(:word, text: "suco", category: pt_drinks)
      insert(:word, text: "coração", category: pt_food)
      insert(:word, text: "coracao", category: pt_drinks)

      # Unplayable entries are ignored
      Repo.insert!(%Forka.Words.Word{text: "", category_id: pt_food.id})
      Repo.insert!(%Forka.Words.Word{text: "   ", category_id: pt_food.id})
      Repo.insert!(%Forka.Words.Word{text: "12345", category_id: pt_food.id})
      Repo.insert!(%Forka.Words.Word{text: "---", category_id: pt_drinks.id})

      # Different language is excluded from pt counts
      insert(:word, text: "coffee", category: en_food)
      insert(:word, text: "tea", category: en_food)

      assert Words.count_distinct_playable_words(language: "pt") == 3
      assert Words.count_distinct_playable_words(language: " PT ", category_ids: []) == 3
      assert Words.count_distinct_playable_words(language: "pt", category_ids: [pt_food.id]) == 2

      assert Words.count_distinct_playable_words(language: "pt", category_ids: [pt_drinks.id]) ==
               3

      assert Words.count_distinct_playable_words(
               language: "pt",
               category_ids: [pt_food.id, pt_drinks.id]
             ) == 3

      assert Words.count_distinct_playable_words(language: "en") == 2
      assert Words.count_distinct_playable_words(language: "pt", category_ids: [en_food.id]) == 0
    end

    test "REQ-01 & EDGE-01: samples up to count distinct playable entries without duplicate starvation" do
      pt_a = insert(:category, name: "A", language: "pt")
      pt_b = insert(:category, name: "B", language: "pt")

      # Many normalized duplicates of "cafe" alongside 3 other distinct words
      insert(:word, text: "café", hint: "Quente", category: pt_a)
      insert(:word, text: "cafe", hint: "Preto", category: pt_a)
      insert(:word, text: "CAFÉ", hint: "Bebida", category: pt_b)
      insert(:word, text: "gato", hint: "Mia", category: pt_a)
      insert(:word, text: "pato", hint: "Grasna", category: pt_a)
      insert(:word, text: "lobo", hint: "Uiva", category: pt_b)
      Repo.insert!(%Forka.Words.Word{text: "   ", category_id: pt_a.id})
      Repo.insert!(%Forka.Words.Word{text: "---", category_id: pt_b.id})

      sampled =
        Words.sample_distinct_playable_words(4,
          language: "pt",
          category_ids: [pt_a.id, pt_b.id]
        )

      assert length(sampled) == 4
      assert Enum.all?(sampled, &WordText.playable_text?(&1.text))
      assert Enum.all?(sampled, &(&1.language == "pt"))

      normalized_keys = Enum.map(sampled, &WordText.normalize_text(&1.text))
      assert MapSet.new(normalized_keys) == MapSet.new(["cafe", "gato", "pato", "lobo"])

      assert Words.sample_distinct_playable_words(0, language: "pt") == []

      short = Words.sample_distinct_playable_words(10, language: "pt", category_ids: [pt_a.id])
      assert length(short) == 3
      assert length(Enum.uniq_by(short, &WordText.normalize_text(&1.text))) == 3
    end
  end
end
