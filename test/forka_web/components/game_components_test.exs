defmodule ForkaWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ForkaWeb.GameComponents

  describe "rope/1" do
    test "renders tries 6..1 with expected fray count and accessible label" do
      for tries <- [6, 5, 4, 2, 1] do
        html = render_component(&rope/1, %{id: "rope-#{tries}", tries: tries, size: :md})
        doc = LazyHTML.from_fragment(html)
        root = LazyHTML.query(doc, "#rope-#{tries}")

        assert LazyHTML.attribute(root, "role") == ["img"]
        assert LazyHTML.attribute(root, "aria-label") == ["Corda: #{tries} de 6 tentativas"]
        assert LazyHTML.attribute(root, "phx-hook") == ["RopeFeedback"]
        assert LazyHTML.attribute(root, "data-tries") == ["#{tries}"]
        assert LazyHTML.text(root) =~ "#{tries} de 6"

        frays = LazyHTML.query(doc, "path.forka-rope-fray")
        assert Enum.count(frays) == (6 - tries) * 2
      end
    end

    test "renders snapped halves at 0 tries and clamps out-of-bounds values" do
      snapped = render_component(&rope/1, %{tries: -2, size: :sm})
      doc = LazyHTML.from_fragment(snapped)

      assert LazyHTML.attribute(LazyHTML.query(doc, "[role=img]"), "aria-label") == [
               "Corda rompida: sem tentativas"
             ]

      assert LazyHTML.text(doc) =~ "rompida"
      assert Enum.count(LazyHTML.query(doc, "g.forka-rope-snap-l")) == 1
      assert Enum.count(LazyHTML.query(doc, "g.forka-rope-snap-r")) == 1

      clamped_high =
        render_component(&rope/1, %{tries: 99, size: :lg, label: false, on_dark: true})

      high_doc = LazyHTML.from_fragment(clamped_high)

      assert LazyHTML.attribute(LazyHTML.query(high_doc, "[role=img]"), "aria-label") == [
               "Corda: 6 de 6 tentativas"
             ]

      refute LazyHTML.text(high_doc) =~ "6 de 6"
    end
  end

  describe "word_tiles/1" do
    test "groups multi-word phrases, preserves hyphens and accents, and reads sr-only text" do
      letters = [
        {:found, "a"},
        {:found, "r"},
        :hidden,
        {:found, "o"},
        {:found, "-"},
        {:found, "í"},
        {:found, "r"},
        {:found, "i"},
        {:found, "s"},
        {:found, " "},
        {:found, "ç"}
      ]

      html = render_component(&word_tiles/1, %{letters: letters, last_letter: "c"})
      doc = LazyHTML.from_fragment(html)

      sr = LazyHTML.text(LazyHTML.query(doc, ".sr-only"))
      assert sr =~ "Palavra: A, R, oculta, O, -, Í, R, I, S, espaço, Ç"

      word_groups = LazyHTML.query(doc, "div[aria-hidden=true] > div")
      assert Enum.count(word_groups) == 2

      highlighted = LazyHTML.query(doc, "span.bg-accent.forka-pop")
      assert Enum.count(highlighted) == 1
      assert LazyHTML.text(highlighted) =~ "Ç"
    end

    test "selects tile size automatically based on longest word length" do
      short = List.duplicate(:hidden, 8)
      medium = List.duplicate(:hidden, 12)
      long = List.duplicate(:hidden, 14)

      assert hd(
               LazyHTML.attribute(
                 LazyHTML.query(
                   LazyHTML.from_fragment(render_component(&word_tiles/1, %{letters: short})),
                   "span"
                 ),
                 "class"
               )
             ) =~ "w-8 h-10"

      assert hd(
               LazyHTML.attribute(
                 LazyHTML.query(
                   LazyHTML.from_fragment(render_component(&word_tiles/1, %{letters: medium})),
                   "span"
                 ),
                 "class"
               )
             ) =~ "w-7 h-9"

      assert hd(
               LazyHTML.attribute(
                 LazyHTML.query(
                   LazyHTML.from_fragment(render_component(&word_tiles/1, %{letters: long})),
                   "span"
                 ),
                 "class"
               )
             ) =~ "w-6 h-8"
    end

    test "renders completed state with success tiles" do
      html =
        render_component(&word_tiles/1, %{
          letters: [{:found, "f"}, {:found, "o"}, {:found, "r"}, {:found, "k"}, {:found, "a"}],
          completed: true
        })

      tiles = LazyHTML.query(LazyHTML.from_fragment(html), "span.bg-success-300")
      assert Enum.count(tiles) == 5
    end
  end

  describe "letter_key/1" do
    test "renders free, correct, wrong, and waiting states with aria-labels" do
      free_doc = LazyHTML.from_fragment(render_component(&letter_key/1, %{letter: "a"}))
      free_btn = LazyHTML.query(free_doc, "button")
      assert LazyHTML.attribute(free_btn, "aria-label") == ["A"]
      assert LazyHTML.attribute(free_btn, "disabled") == []

      ok_doc =
        LazyHTML.from_fragment(render_component(&letter_key/1, %{letter: "e", state: :correct}))

      ok_btn = LazyHTML.query(ok_doc, "button")
      assert LazyHTML.attribute(ok_btn, "aria-label") == ["E, certa"]
      assert LazyHTML.attribute(ok_btn, "disabled") == [""]

      bad_doc =
        LazyHTML.from_fragment(render_component(&letter_key/1, %{letter: "x", state: :wrong}))

      bad_btn = LazyHTML.query(bad_doc, "button")
      assert LazyHTML.attribute(bad_btn, "aria-label") == ["X, errada"]
      assert LazyHTML.attribute(bad_btn, "disabled") == [""]

      wait_doc =
        LazyHTML.from_fragment(render_component(&letter_key/1, %{letter: "b", waiting: true}))

      assert LazyHTML.attribute(LazyHTML.query(wait_doc, "button"), "disabled") == [""]
    end
  end

  describe "keyboard/1" do
    test "renders 26 A-Z keys, supports Guess structs and maps, and handles waiting state" do
      guesses = [%{letter: "a", correct?: true}, %{letter: "z", correct?: false}]

      html =
        render_component(&keyboard/1, %{
          id: "kb-1",
          guesses: guesses,
          waiting: true,
          wait_message: "Aguarde: vez de Bruno"
        })

      doc = LazyHTML.from_fragment(html)
      root = LazyHTML.query(doc, "#kb-1")
      assert LazyHTML.attribute(root, "phx-hook") == ["GameKeyboard"]
      assert LazyHTML.attribute(root, "data-disabled") == ["true"]
      assert LazyHTML.text(doc) =~ "Aguarde: vez de Bruno"

      keys = LazyHTML.query(doc, "button[data-letter]")
      assert Enum.count(keys) == 26

      assert LazyHTML.attribute(LazyHTML.query(doc, ~s|button[data-letter="A"]|), "aria-label") ==
               ["A, certa"]

      assert LazyHTML.attribute(LazyHTML.query(doc, ~s|button[data-letter="Z"]|), "aria-label") ==
               ["Z, errada"]

      assert LazyHTML.attribute(LazyHTML.query(doc, ~s|button[data-letter="M"]|), "disabled") == [
               ""
             ]

      map_html =
        render_component(&keyboard/1, %{
          id: "kb-2",
          guesses: %{"c" => :correct}
        })

      map_doc = LazyHTML.from_fragment(map_html)

      assert LazyHTML.attribute(
               LazyHTML.query(map_doc, ~s|button[data-letter="C"]|),
               "aria-label"
             ) == ["C, certa"]

      assert LazyHTML.attribute(LazyHTML.query(map_doc, ~s|button[data-letter="D"]|), "disabled") ==
               []
    end
  end
end
