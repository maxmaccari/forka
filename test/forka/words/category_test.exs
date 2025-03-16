defmodule Forka.Words.CategoryTest do
  use Forka.DataCase, async: true

  alias Forka.Words.Category

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Category.changeset(%Category{}, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates minimum length of name" do
      changeset = Category.changeset(%Category{}, %{name: "a"})
      assert %{name: ["must have at least 2 characters"]} = errors_on(changeset)
    end

    test "validates language format" do
      invalid_languages = ["english", "e", "123", "en-us", "EN"]

      for lang <- invalid_languages do
        changeset = Category.changeset(%Category{}, %{name: "valid name", language: lang})

        assert %{
                 language: [
                   "must be a valid ISO language code (two lowercase letters, optionally followed by a hyphen and two uppercase letters for region)"
                 ]
               } = errors_on(changeset)
      end
    end

    test "accepts valid language formats" do
      valid_languages = ["en", "pt", "es", "fr-FR", "pt-BR"]

      for lang <- valid_languages do
        changeset = Category.changeset(%Category{}, %{name: "valid name", language: lang})
        assert changeset.valid?
      end
    end

    test "enforces unique constraint on name and language" do
      # This test requires database interaction
      {:ok, _} = Repo.insert(%Category{name: "Unique Name", language: "en"})

      {:error, changeset} =
        %Category{}
        |> Category.changeset(%{name: "Unique Name", language: "en"})
        |> Repo.insert()

      assert %{name: ["has already been taken"]} = errors_on(changeset)

      # Different language should work
      changeset = Category.changeset(%Category{}, %{name: "Unique Name", language: "pt"})
      assert changeset.valid?
    end

    test "name is case-insensitive for uniqueness constraint" do
      # This test requires database interaction
      {:ok, _} = Repo.insert(%Category{name: "Unique Name", language: "en"})

      {:error, changeset} =
        %Category{}
        |> Category.changeset(%{name: "UNIQUE NAME", language: "en"})
        |> Repo.insert()

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
