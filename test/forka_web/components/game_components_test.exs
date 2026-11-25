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

    test "R-04a: renders Corda.dc.html capsule body, diagonal twists, neck-anchored frays, and data-state for tries 6..1" do
      expected_states = %{
        6 => "intact",
        5 => "frayed",
        4 => "frayed",
        3 => "frayed",
        2 => "frayed",
        1 => "critical"
      }

      for tries <- 6..1//-1 do
        html = render_component(&rope/1, %{tries: tries, size: :md})
        doc = LazyHTML.from_fragment(html)
        root = LazyHTML.query(doc, "span[role=img]")

        assert Enum.count(root) == 1
        assert LazyHTML.attribute(root, "data-tries") == ["#{tries}"]
        assert LazyHTML.attribute(root, "data-state") == [expected_states[tries]]
        assert LazyHTML.attribute(root, "phx-hook") == []

        body = LazyHTML.query(doc, "svg > path.fill-rope.stroke-rope-edge")
        assert Enum.count(body) == 1
        assert LazyHTML.attribute(body, "stroke-width") == ["1.1"]
        [body_d] = LazyHTML.attribute(body, "d")
        assert body_d =~ "M8 7 H50 C56 7 56 "
        assert body_d =~ "H112 A5 5 0 0 1 112 17 H70"
        assert body_d =~ "H8 A5 5 0 0 1 8 7 Z"

        twist_group = LazyHTML.query(doc, "svg > g.stroke-rope-twist")
        assert LazyHTML.attribute(twist_group, "stroke-width") == ["1.2"]
        twist_lines = LazyHTML.query(doc, "svg > g.stroke-rope-twist > line")
        assert Enum.count(twist_lines) == if(tries == 6, do: 20, else: 16)
        assert LazyHTML.attribute(twist_lines, "y1") |> Enum.uniq() == ["16.2"]
        assert LazyHTML.attribute(twist_lines, "y2") |> Enum.uniq() == ["7.8"]

        fray_group = LazyHTML.query(doc, "svg > g.stroke-rope-edge")
        assert LazyHTML.attribute(fray_group, "stroke-width") == ["0.9"]
        frays = LazyHTML.query(doc, "path.forka-rope-fray")
        assert Enum.count(frays) == (6 - tries) * 2
      end

      # Spot-check neck-anchored fray origin coordinates match Corda.dc.html at 5 and 1 tries
      doc5 = LazyHTML.from_fragment(render_component(&rope/1, %{tries: 5}))

      assert LazyHTML.attribute(LazyHTML.query(doc5, "path.forka-rope-fray"), "d") == [
               "M53.0 7.8 q -0.8 -1.7 -1.6 -2.9",
               "M60.0 16.2 q -0.8 2.4 -1.6 4.0"
             ]

      doc1 = LazyHTML.from_fragment(render_component(&rope/1, %{tries: 1}))
      frays1 = LazyHTML.attribute(LazyHTML.query(doc1, "path.forka-rope-fray"), "d")

      assert Enum.take(frays1, 2) == [
               "M53.0 11.0 q -0.8 -2.3 -1.6 -3.9",
               "M54.4 13.0 q -0.8 3.0 -1.6 5.0"
             ]
    end

    test "R-04b: renders Corda.dc.html jagged snapped halves, 8 twists per half, and 4 torn end fibers per side at 0 tries" do
      html = render_component(&rope/1, %{tries: 0, size: :lg, label: false})
      doc = LazyHTML.from_fragment(html)
      root = LazyHTML.query(doc, "span[role=img]")

      assert LazyHTML.attribute(root, "data-tries") == ["0"]
      assert LazyHTML.attribute(root, "data-state") == ["snapped"]
      assert LazyHTML.attribute(root, "aria-label") == ["Corda rompida: sem tentativas"]
      assert Enum.count(LazyHTML.query(doc, "path.forka-rope-fray")) == 0

      left_body = LazyHTML.query(doc, "g.forka-rope-snap-l > path.fill-rope.stroke-rope-edge")

      assert LazyHTML.attribute(left_body, "d") == [
               "M8 7 H54 L56.5 8.8 L54.5 10.4 L57 12 L54.5 13.6 L56.5 15.2 L54 17 H8 A5 5 0 0 1 8 7 Z"
             ]

      assert LazyHTML.attribute(left_body, "stroke-width") == ["1.1"]

      left_twists = LazyHTML.query(doc, "g.forka-rope-snap-l > g.stroke-rope-twist > line")
      assert Enum.count(left_twists) == 8
      assert LazyHTML.attribute(left_twists, "x1") == ~w(10 15 20 25 30 35 40 45)
      assert LazyHTML.attribute(left_twists, "y1") |> Enum.uniq() == ["16.2"]
      assert LazyHTML.attribute(left_twists, "y2") |> Enum.uniq() == ["7.8"]

      left_fibers = LazyHTML.query(doc, "g.forka-rope-snap-l > path.stroke-rope-edge[fill=none]")

      assert LazyHTML.attribute(left_fibers, "d") == [
               "M56 9 L59.5 6.5 M57 12 L61 12.6 M56 15 L59 18 M55 10.5 L58 9.5"
             ]

      assert LazyHTML.attribute(left_fibers, "stroke-width") == ["0.9"]

      right_body = LazyHTML.query(doc, "g.forka-rope-snap-r > path.fill-rope.stroke-rope-edge")

      assert LazyHTML.attribute(right_body, "d") == [
               "M66 7 L63.5 8.8 L65.5 10.4 L63 12 L65.5 13.6 L63.5 15.2 L66 17 H112 A5 5 0 0 0 112 7 Z"
             ]

      assert LazyHTML.attribute(right_body, "stroke-width") == ["1.1"]

      right_twists = LazyHTML.query(doc, "g.forka-rope-snap-r > g.stroke-rope-twist > line")
      assert Enum.count(right_twists) == 8
      assert LazyHTML.attribute(right_twists, "x1") == ~w(70 75 80 85 90 95 100 105)
      assert LazyHTML.attribute(right_twists, "y1") |> Enum.uniq() == ["16.2"]
      assert LazyHTML.attribute(right_twists, "y2") |> Enum.uniq() == ["7.8"]

      right_fibers = LazyHTML.query(doc, "g.forka-rope-snap-r > path.stroke-rope-edge[fill=none]")

      assert LazyHTML.attribute(right_fibers, "d") == [
               "M64 9 L60.5 6.5 M63 12 L59 11.4 M64 15 L61 18 M65 13.5 L62 14.5"
             ]

      assert LazyHTML.attribute(right_fibers, "stroke-width") == ["0.9"]
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

      Enum.each(LazyHTML.attribute(word_groups, "class"), fn group_class ->
        assert group_class =~ "max-w-full"
        assert group_class =~ "overflow-x-auto"
      end)

      highlighted = LazyHTML.query(doc, "span.bg-accent.forka-pop")
      assert Enum.count(highlighted) == 1
      assert LazyHTML.text(highlighted) =~ "Ç"
    end

    test "selects tile size automatically based on longest word length" do
      short = List.duplicate(:hidden, 8)
      medium = List.duplicate(:hidden, 10)
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
             ) =~ "w-5 h-8"
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
      assert hd(LazyHTML.attribute(root, "class")) =~ "@container"
      grid_class = hd(LazyHTML.attribute(LazyHTML.query(doc, "#kb-1 > div.grid"), "class"))
      assert grid_class =~ "grid-cols-6"
      assert grid_class =~ "gap-1"
      assert grid_class =~ "@kb-7:grid-cols-7"
      assert grid_class =~ "@kb-13:grid-cols-13"
      assert grid_class =~ "@kb-13:gap-2"
      refute grid_class =~ "md:grid-cols-13"
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
