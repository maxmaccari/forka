defmodule Forka.Games.RoomSettingsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Forka.Games.RoomSettings
  alias Forka.Games.Schemas.WordOptions

  describe "WordOptions.normalize/1 and changeset/2 compatibility" do
    test "AC-02: normalizes nil, keyword lists, maps, and structs to %WordOptions{}" do
      assert WordOptions.normalize(nil) == %WordOptions{language: "en", category_ids: []}

      assert WordOptions.normalize(language: "pt", category_ids: ["id-1"]) ==
               %WordOptions{language: "pt", category_ids: ["id-1"]}

      assert WordOptions.normalize(%{"language" => "pt"}) ==
               %WordOptions{language: "pt", category_ids: []}

      assert WordOptions.normalize(%WordOptions{language: nil, category_ids: nil}) ==
               %WordOptions{language: "en", category_ids: []}
    end

    test "AC-02: legacy WordOptions.changeset/2 remains permissive for existing persisted languages" do
      cs = WordOptions.changeset(%WordOptions{}, %{language: "es", category_ids: []})
      assert cs.valid?
    end
  end

  describe "RoomSettings.changeset/3" do
    test "AC-02: accepts valid name, capacity 2..6, normalized language, and allowed categories" do
      cat_1 = Ecto.UUID.generate()
      cat_2 = Ecto.UUID.generate()

      changeset =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{
            "name" => "  Noite de palavras  ",
            "max_players" => "6",
            "word_options" => %{"language" => " PT ", "category_ids" => [cat_1, cat_2]}
          },
          allowed_category_ids: [cat_1, cat_2]
        )

      assert changeset.valid?
      settings = Ecto.Changeset.apply_changes(changeset)
      assert settings.name == "Noite de palavras"
      assert settings.max_players == 6
      assert settings.word_options == %WordOptions{language: "pt", category_ids: [cat_1, cat_2]}
    end

    test "AC-02: rejects blank, whitespace-only, and over-60-character room names" do
      blank = RoomSettings.changeset(RoomSettings.new(), %{name: "   ", max_players: 4})
      refute blank.valid?
      assert {"can't be blank", _} = blank.errors[:name]

      too_long =
        RoomSettings.changeset(RoomSettings.new(), %{
          name: String.duplicate("a", 61),
          max_players: 4
        })

      refute too_long.valid?
      assert {"should be at most %{count} character(s)", opts} = too_long.errors[:name]
      assert opts[:count] == 60
    end

    test "AC-02: rejects max_players outside 2..6" do
      too_few = RoomSettings.changeset(RoomSettings.new(), %{name: "Sala", max_players: 1})
      refute too_few.valid?
      assert too_few.errors[:max_players]

      too_many = RoomSettings.changeset(RoomSettings.new(), %{name: "Sala", max_players: 7})
      refute too_many.valid?
      assert too_many.errors[:max_players]
    end

    test "EDGE-01: rejects max_players below current occupancy when min_players option is set" do
      changeset =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{name: "Sala", max_players: 2},
          min_players: 4
        )

      refute changeset.valid?

      assert {"não pode ser menor que o número atual de jogadores (%{count})", opts} =
               changeset.errors[:max_players]

      assert opts[:count] == 4
    end

    test "AC-02: rejects unsupported word language" do
      changeset =
        RoomSettings.changeset(RoomSettings.new(), %{
          name: "Sala",
          max_players: 4,
          word_options: %{language: "es", category_ids: []}
        })

      refute changeset.valid?
      word_opts_cs = Ecto.Changeset.get_change(changeset, :word_options)
      assert word_opts_cs.errors[:language]
    end

    test "EDGE-02: rejects malformed non-UUID category_ids and stale/disallowed UUIDs" do
      valid_id = Ecto.UUID.generate()
      stale_id = Ecto.UUID.generate()

      malformed =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{
            name: "Sala",
            max_players: 4,
            word_options: %{language: "pt", category_ids: ["not-a-uuid"]}
          },
          allowed_category_ids: [valid_id]
        )

      refute malformed.valid?
      malformed_wo = Ecto.Changeset.get_change(malformed, :word_options)

      assert {"contém categorias indisponíveis para o idioma selecionado", _} =
               malformed_wo.errors[:category_ids]

      stale =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{
            name: "Sala",
            max_players: 4,
            word_options: %{language: "pt", category_ids: [valid_id, stale_id]}
          },
          allowed_category_ids: [valid_id]
        )

      refute stale.valid?
      stale_wo = Ecto.Changeset.get_change(stale, :word_options)

      assert {"contém categorias indisponíveis para o idioma selecionado", _} =
               stale_wo.errors[:category_ids]
    end

    test "EDGE-02: handles explicit nils safely and canonicalizes uppercase UUIDs" do
      cat_id = Ecto.UUID.generate()
      upper_id = String.upcase(cat_id)

      nil_cs =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{name: nil, max_players: 4, word_options: %{language: nil, category_ids: nil}},
          allowed_category_ids: []
        )

      refute nil_cs.valid?
      assert {"can't be blank", _} = nil_cs.errors[:name]
      assert Ecto.Changeset.get_change(nil_cs, :word_options).errors[:language]

      upper_cs =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{
            name: "Sala Canonical",
            max_players: 4,
            word_options: %{language: "pt", category_ids: [upper_id]}
          },
          allowed_category_ids: [cat_id]
        )

      assert upper_cs.valid?
      applied = Ecto.Changeset.apply_changes(upper_cs)
      assert applied.word_options.category_ids == [cat_id]
    end

    test "AC-02: accepts empty category_ids as all categories" do
      changeset =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{
            name: "Sala",
            max_players: 4,
            word_options: %{language: "pt", category_ids: []}
          },
          allowed_category_ids: []
        )

      assert changeset.valid?
    end

    test "AC-02: rejects explicit nil word_options" do
      changeset =
        RoomSettings.changeset(RoomSettings.new(), %{
          name: "Sala",
          max_players: 4,
          word_options: nil
        })

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:word_options]
    end

    test "AC-04: rejects name-only edit when effective legacy language is unsupported" do
      legacy = %RoomSettings{
        name: "Sala ES",
        max_players: 4,
        word_options: %WordOptions{language: "es", category_ids: []}
      }

      cs_name_only = RoomSettings.changeset(legacy, %{name: "Sala Renomeada"})
      refute cs_name_only.valid?
      assert Ecto.Changeset.get_change(cs_name_only, :word_options).errors[:language]

      cs_fixed_lang =
        RoomSettings.changeset(legacy, %{
          name: "Sala Renomeada",
          word_options: %{language: "pt", category_ids: []}
        })

      assert cs_fixed_lang.valid?
    end

    test "EDGE-02: enforces max category count before normalization and lookup" do
      limit = WordOptions.max_categories()
      id = Ecto.UUID.generate()
      oversized = List.duplicate(id, limit + 1)

      assert {"pt", []} =
               RoomSettings.extract_lookup_inputs(RoomSettings.new(), %{
                 "word_options" => %{"language" => "pt", "category_ids" => oversized}
               })

      cs =
        RoomSettings.changeset(
          RoomSettings.new(),
          %{
            name: "Sala",
            max_players: 4,
            word_options: %{language: "pt", category_ids: oversized}
          },
          allowed_category_ids: [id]
        )

      refute cs.valid?
      wo_cs = Ecto.Changeset.get_change(cs, :word_options)

      assert {"deve ter no máximo %{count} categorias", opts} = wo_cs.errors[:category_ids]
      assert opts[:count] == limit
    end

    property "EDGE-01: accepts max_players iff within 2..6 and >= live occupancy" do
      check all max_players <- integer(-2..10),
                occupancy <- integer(0..8) do
        cs =
          RoomSettings.changeset(
            RoomSettings.new(),
            %{name: "Sala", max_players: max_players},
            min_players: occupancy
          )

        expected_valid? = max_players in 2..6 and max_players >= occupancy
        assert cs.valid? == expected_valid?
      end
    end
  end
end
