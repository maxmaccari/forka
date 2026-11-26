defmodule ForkaWeb.GameComponents do
  @moduledoc """
  Stateless, pure presentation components for Forka's game pieces and keyboard.

  Includes `<.rope>`, `<.word_tiles>`, `<.letter_key>`, and `<.keyboard>`.
  """
  use Phoenix.Component

  alias Forka.WordText

  @alphabet WordText.supported_letters()
  @neck_half_heights {0.0, 1.0, 1.8, 2.6, 3.4, 4.2, 5.0}

  @doc """
  Renders the Forka twisted rope SVG that wears out over 6 tries and snaps at 0.
  """
  attr :id, :string, default: nil
  attr :tries, :integer, required: true
  attr :size, :atom, default: :md, values: [:lg, :md, :sm]
  attr :label, :boolean, default: true
  attr :on_dark, :boolean, default: false
  attr :class, :string, default: nil

  def rope(assigns) do
    t = assigns.tries |> max(0) |> min(6)
    {svg_w, svg_h} = rope_dimensions(assigns.size)
    neck_h = elem(@neck_half_heights, t)

    aria_label =
      if t == 0 do
        "Corda rompida: sem tentativas"
      else
        "Corda: #{t} de 6 tentativas"
      end

    assigns =
      assigns
      |> assign(:t, t)
      |> assign(:state, rope_state(t))
      |> assign(:svg_w, svg_w)
      |> assign(:svg_h, svg_h)
      |> assign(:aria_label, aria_label)
      |> assign(:body_path, rope_body_path(neck_h))
      |> assign(:twists, rope_twists(t))
      |> assign(:frays, rope_frays(t, neck_h))

    ~H"""
    <span
      id={@id}
      role="img"
      aria-label={@aria_label}
      phx-hook={@id && "RopeFeedback"}
      data-tries={@t}
      data-state={@state}
      class={["inline-flex items-center gap-2 leading-none align-middle", @class]}
    >
      <svg
        viewBox="0 0 120 24"
        width={@svg_w}
        height={@svg_h}
        class="block shrink-0 overflow-visible"
        aria-hidden="true"
      >
        <%= if @t > 0 do %>
          <path
            d={@body_path}
            class="fill-rope stroke-rope-edge"
            stroke-width="1.1"
            stroke-linejoin="round"
          />
          <g class="stroke-rope-twist" stroke-width="1.2" stroke-linecap="round">
            <line
              :for={x <- @twists}
              :key={x}
              x1={x}
              y1="16.2"
              x2={fmt_coord(x + 3.6)}
              y2="7.8"
            />
          </g>
          <g class="stroke-rope-edge" fill="none" stroke-width="0.9" stroke-linecap="round">
            <path
              :for={{d, idx} <- Enum.with_index(@frays)}
              :key={idx}
              d={d}
              class="forka-rope-fray"
            />
          </g>
        <% else %>
          <g class="forka-rope-snap-l">
            <path
              d={snap_left_body()}
              class="fill-rope stroke-rope-edge"
              stroke-width="1.1"
              stroke-linejoin="round"
            />
            <g class="stroke-rope-twist" stroke-width="1.2" stroke-linecap="round">
              <line
                :for={x <- snap_left_twists()}
                :key={x}
                x1={x}
                y1="16.2"
                x2={fmt_coord(x + 3.6)}
                y2="7.8"
              />
            </g>
            <path
              d={snap_left_fibers()}
              class="stroke-rope-edge"
              fill="none"
              stroke-width="0.9"
              stroke-linecap="round"
            />
          </g>
          <g class="forka-rope-snap-r">
            <path
              d={snap_right_body()}
              class="fill-rope stroke-rope-edge"
              stroke-width="1.1"
              stroke-linejoin="round"
            />
            <g class="stroke-rope-twist" stroke-width="1.2" stroke-linecap="round">
              <line
                :for={x <- snap_right_twists()}
                :key={x}
                x1={x}
                y1="16.2"
                x2={fmt_coord(x + 3.6)}
                y2="7.8"
              />
            </g>
            <path
              d={snap_right_fibers()}
              class="stroke-rope-edge"
              fill="none"
              stroke-width="0.9"
              stroke-linecap="round"
            />
          </g>
        <% end %>
      </svg>

      <span
        :if={@label}
        class={[
          "font-sans font-extrabold tabular-nums whitespace-nowrap",
          rope_label_size(@size),
          rope_label_color(@t, @on_dark)
        ]}
      >
        {rope_label_text(@t, @size)}
      </span>
    </span>
    """
  end

  defp rope_dimensions(:lg), do: {240, 48}
  defp rope_dimensions(:md), do: {132, 26}
  defp rope_dimensions(:sm), do: {52, 13}

  defp rope_state(6), do: "intact"
  defp rope_state(1), do: "critical"
  defp rope_state(0), do: "snapped"
  defp rope_state(_t), do: "frayed"

  defp rope_body_path(h) do
    top = fmt_coord(12 - h)
    bot = fmt_coord(12 + h)

    "M8 7 H50 C56 7 56 #{top} 60 #{top} C64 #{top} 64 7 70 7 H112 A5 5 0 0 1 112 17 H70 C64 17 64 #{bot} 60 #{bot} C56 #{bot} 56 17 50 17 H8 A5 5 0 0 1 8 7 Z"
  end

  defp rope_twists(6), do: Enum.to_list(10..108//5)
  defp rope_twists(t) when t > 0, do: for(x <- 10..108//5, x <= 46 or x >= 70, do: x)
  defp rope_twists(_t), do: []

  defp rope_frays(t, _h) when t <= 0 or t >= 6, do: []

  defp rope_frays(t, h) do
    count = (6 - t) * 2

    for i <- 0..(count - 1) do
      side = if rem(i, 2) == 1, do: 1, else: -1
      x = 53 + i * 14 / count
      y0 = 12 + side * h
      len = 2.6 + rem(i, 3) * 1.1 + (6 - t) * 0.25
      dx = if rem(i, 4) < 2, do: -1.6, else: 1.6

      "M#{fmt_fixed(x)} #{fmt_fixed(y0)} q #{fmt_fixed(dx / 2)} #{fmt_fixed(side * len * 0.6)} #{fmt_fixed(dx)} #{fmt_fixed(side * len)}"
    end
  end

  defp fmt_coord(val) do
    rounded = Float.round(val * 1.0, 1)

    if rounded == trunc(rounded) * 1.0 do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 1)
    end
  end

  defp fmt_fixed(val), do: :erlang.float_to_binary(val * 1.0, decimals: 1)

  defp snap_left_body do
    "M8 7 H54 L56.5 8.8 L54.5 10.4 L57 12 L54.5 13.6 L56.5 15.2 L54 17 H8 A5 5 0 0 1 8 7 Z"
  end

  defp snap_right_body do
    "M66 7 L63.5 8.8 L65.5 10.4 L63 12 L65.5 13.6 L63.5 15.2 L66 17 H112 A5 5 0 0 0 112 7 Z"
  end

  defp snap_left_twists, do: Enum.to_list(10..48//5)
  defp snap_right_twists, do: Enum.to_list(70..108//5)

  defp snap_left_fibers do
    "M56 9 L59.5 6.5 M57 12 L61 12.6 M56 15 L59 18 M55 10.5 L58 9.5"
  end

  defp snap_right_fibers do
    "M64 9 L60.5 6.5 M63 12 L59 11.4 M64 15 L61 18 M65 13.5 L62 14.5"
  end

  defp rope_label_size(:lg), do: "text-lg"
  defp rope_label_size(:md), do: "text-sm"
  defp rope_label_size(:sm), do: "text-xs"

  defp rope_label_color(_t, true), do: "text-hero-ink"
  defp rope_label_color(t, false) when t <= 1, do: "text-danger-ink"
  defp rope_label_color(_t, false), do: "text-ink-muted"

  defp rope_label_text(0, _size), do: "rompida"
  defp rope_label_text(t, :sm), do: "#{t}/6"
  defp rope_label_text(t, _size), do: "#{t} de 6"

  @doc """
  Renders masked word tiles grouped by words so wrapping never splits a word.
  """
  attr :letters, :list, required: true
  attr :last_letter, :string, default: nil
  attr :completed, :boolean, default: false
  attr :size, :atom, default: :auto, values: [:auto, :lg, :md, :sm, :xs]
  attr :class, :string, default: nil

  def word_tiles(assigns) do
    words = split_word_groups(assigns.letters)
    resolved_size = resolve_tile_size(assigns.size, words)
    folded_last = fold_ascii(assigns.last_letter)

    assigns =
      assigns
      |> assign(:words, words)
      |> assign(:resolved_size, resolved_size)
      |> assign(:folded_last, folded_last)
      |> assign(:spoken_text, build_spoken_text(words))

    ~H"""
    <div class={@class}>
      <p class="sr-only">Palavra: {@spoken_text}</p>
      <div aria-hidden="true" class="flex flex-wrap items-center justify-center gap-3">
        <div
          :for={word <- @words}
          class="flex max-w-full flex-nowrap gap-1 overflow-x-auto pb-1"
        >
          <span
            :for={cell <- word}
            class={[
              "inline-flex shrink-0 items-center justify-center font-display font-bold uppercase select-none",
              tile_size_class(@resolved_size),
              tile_state_class(cell, @folded_last, @completed)
            ]}
          >
            {tile_char(cell)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp split_word_groups(letters) do
    letters
    |> Enum.chunk_by(&(&1 == {:found, " "}))
    |> Enum.reject(&match?([{:found, " "} | _], &1))
  end

  defp resolve_tile_size(:auto, []), do: :md

  defp resolve_tile_size(:auto, words) do
    max_len = words |> Enum.map(&length/1) |> Enum.max()

    cond do
      max_len <= 8 -> :md
      max_len <= 10 -> :sm
      true -> :xs
    end
  end

  defp resolve_tile_size(size, _words), do: size

  defp tile_size_class(:lg), do: "w-12 h-14 text-3xl rounded-md"
  defp tile_size_class(:md), do: "w-8 h-10 text-xl rounded-sm"
  defp tile_size_class(:sm), do: "w-7 h-9 text-lg rounded-sm"
  defp tile_size_class(:xs), do: "w-5 h-8 text-sm rounded-sm sm:w-6 sm:h-8 sm:text-base"

  defp tile_state_class(_cell, _folded_last, true) do
    "bg-success-300 text-success-900 shadow-lip-success"
  end

  defp tile_state_class(:hidden, _folded_last, false) do
    "bg-sunken shadow-lip-tile ring-2 ring-inset ring-line"
  end

  defp tile_state_class({:found, ch}, folded_last, false) do
    if folded_last != nil and fold_ascii(ch) == folded_last do
      "bg-accent text-on-player shadow-lip-accent forka-pop"
    else
      "bg-tile text-ink shadow-lip-tile ring-2 ring-inset ring-line"
    end
  end

  defp tile_char(:hidden), do: ""
  defp tile_char({:found, ch}), do: String.upcase(ch)

  defp fold_ascii(nil), do: nil
  defp fold_ascii(""), do: nil

  defp fold_ascii(str) do
    str
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.upcase()
  end

  defp build_spoken_text(words) do
    Enum.map_join(words, ", espaço, ", fn word ->
      Enum.map_join(word, ", ", fn
        :hidden -> "oculta"
        {:found, ch} -> String.upcase(ch)
      end)
    end)
  end

  @doc """
  Renders a single A–Z letter key button.
  """
  attr :letter, :string, required: true
  attr :state, :atom, default: :free, values: [:free, :correct, :wrong]
  attr :waiting, :boolean, default: false
  attr :size, :atom, default: :md, values: [:md, :lg]
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled phx-click phx-value-letter)

  def letter_key(assigns) do
    upcase = String.upcase(assigns.letter)
    is_disabled = assigns.state != :free or assigns.waiting or assigns.rest[:disabled] == true

    aria_label =
      case assigns.state do
        :free -> upcase
        :correct -> "#{upcase}, certa"
        :wrong -> "#{upcase}, errada"
      end

    assigns =
      assigns
      |> assign(:upcase, upcase)
      |> assign(:is_disabled, is_disabled)
      |> assign(:aria_label, aria_label)

    ~H"""
    <button
      type="button"
      data-letter={@upcase}
      disabled={@is_disabled}
      aria-label={@aria_label}
      class={[
        "inline-flex items-center justify-center rounded-sm font-display font-semibold transition select-none",
        key_size_class(@size),
        key_state_class(@state, @waiting),
        @class
      ]}
      {@rest}
    >
      {@upcase}
    </button>
    """
  end

  defp key_size_class(:md), do: "min-h-12 text-base"
  defp key_size_class(:lg), do: "h-14 text-lg"

  defp key_state_class(:correct, _waiting) do
    "bg-success-soft text-success-ink ring-2 ring-inset ring-success-ink cursor-default"
  end

  defp key_state_class(:wrong, _waiting) do
    "bg-sunken text-ink-subtle line-through decoration-2 cursor-default"
  end

  defp key_state_class(:free, true) do
    "bg-sunken text-ink-subtle ring-1 ring-inset ring-line cursor-not-allowed"
  end

  defp key_state_class(:free, false) do
    "bg-surface text-ink shadow-lip-tile ring-1 ring-inset ring-line hover:bg-canvas active:translate-y-0.5 active:shadow-none"
  end

  @doc """
  Renders the responsive A–Z 26-key game keyboard with physical keyboard hook.
  """
  attr :id, :string, required: true
  attr :guesses, :any, default: []
  attr :disabled, :boolean, default: false
  attr :waiting, :boolean, default: false
  attr :wait_message, :string, default: nil
  attr :on_guess, :string, default: "guess_letter"
  attr :size, :atom, default: :md, values: [:md, :lg]
  attr :class, :string, default: nil

  def keyboard(assigns) do
    state_map = normalize_guesses(assigns.guesses)

    assigns =
      assigns
      |> assign(:alphabet, @alphabet)
      |> assign(:state_map, state_map)

    ~H"""
    <div
      id={@id}
      phx-hook="GameKeyboard"
      data-disabled={to_string(@disabled or @waiting)}
      class={["@container", @class]}
    >
      <p
        :if={@waiting && @wait_message}
        aria-live="polite"
        class="mb-3 text-center text-sm font-bold text-ink-muted"
      >
        {@wait_message}
      </p>
      <div class="grid grid-cols-6 gap-1 @kb-7:grid-cols-7 @kb-13:grid-cols-13 @kb-13:gap-2">
        <.letter_key
          :for={letter <- @alphabet}
          :key={letter}
          letter={letter}
          state={Map.get(@state_map, letter, :free)}
          waiting={@waiting or @disabled}
          size={@size}
          phx-click={@on_guess}
          phx-value-letter={letter}
        />
      </div>
    </div>
    """
  end

  defp normalize_guesses(guesses) when is_map(guesses) do
    Map.new(guesses, fn {k, v} -> {String.upcase(to_string(k)), v} end)
  end

  defp normalize_guesses(guesses) when is_list(guesses) do
    Map.new(guesses, fn guess ->
      state = if guess.correct?, do: :correct, else: :wrong
      {String.upcase(to_string(guess.letter)), state}
    end)
  end
end
