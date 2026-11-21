---
trigger: always_on
description: UI directives §4–§9: product patterns, component architecture, recipes, LiveView behaviour, anti-patterns and the pre-ship checklist
---

# UI Directives: patterns, components and checks

Part of the UI directives; start at `ui.md`. The app's `ui-profile.md` wins over these defaults.

## 4. Product patterns

1. **One skeleton for every entity:** list page (header → optional filter bar → cards) → detail page → owner/admin table. Every entity shares the same card anatomy and badge component.
2. **Card anatomy:** eyebrow or badge → title → meta line → description → one primary action, in the same order in every list. A featured or most-recent item may add a media band on top.
3. **One badge component for every status,** with human labels, wrapped by a domain component (`<.order_status>`), used on cards, detail pages and tables.
4. **Gated actions become contextual CTAs** ("Log in to book these dates"). Send `return_to` and bring the user back to the same page after login.
5. **Filters apply live, sync to the URL** (`push_patch`), **show a result count, offer Reset, and render an empty state that names the query.** All four, every time.
6. **Detail-page anatomy:** media beside badge → title → subtitle → meta line → description → actions; related items in a sidebar, and a "← All items" link.
7. **Meta lines join two or three facts with middots** via `<.intersperse>`: `10 nights · $1,000`, in `text-ink-subtle`.
8. **Activity timelines for history and social proof:** actor in bold, verb in `text-ink-subtle`, an optional quote, a vertical connector.
9. **Celebrate milestones with a `hero` banner and an SVG icon,** at most once per screen. Gradients and emoji are exceptions (EX-02, EX-03).
10. **One signature motif, one illustration style, at most two moments of delight per screen.** Record the motif in the profile.
11. **Microcopy with personality, but clear first:** CTAs say what happens ("Get a ticket"), counts invite ("24 places await"), errors say how to fix ("Give the prize a name").
12. **Forms:** field errors under the field, form-level errors in an alert at the top. If the primary button stays disabled until the form is valid, say why.
13. **Units on numbers, currency on money, years only on dates outside the current year ("Oct 11", but "Oct 11, 2025"), humanised enums** ("Upcoming", never `upcoming`).
14. **Make sharing first-class** where it matters: a read-only URL field with a Copy button and a "Copied!" confirmation (`aria-live="polite"`). Show choices visually (previews), not only by name.
15. **Never ship generator leftovers:** no "Listing X" headings, no "· Phoenix Framework" in `<.live_title>`, no demo buttons.

### 4.1 Feedback and states
- **Every async region has three designed states:** loading (a content-sized skeleton), failed (an alert with Retry, never stack traces or internal fields) and empty (why it's empty and what to do next).
- **Empty states:** an icon in a `bg-brand-soft` circle, short copy, one emphasised action. Hide tabs and filters that do nothing yet.
- **Real-time shows where it happens:** new items stream into lists, counters tick, presence updates, deleted rows fade out.
- **Announce async results** in an `aria-live="polite"` region (saved, copied, deleted).
- **Motion:** `JS` transitions at 150–300ms (`ease-out` in, `ease-in` out); decorative ones behind `motion-safe:`.

### 4.2 Destructive and irreversible actions
- **Style them as distinct:** `danger-link` on the page, never the same style as Edit.
- **Confirm in a modal that names the object and the consequence** ("Delete *Cooking class*? This removes 12 bookings."). Never `data-confirm` (the native `confirm()`).
- **Confirm irreversible actions too,** such as drawing a winner or closing a period. Reversible, frequent actions don't get a modal: they run and offer Undo (§14.3).
- Inside the modal, the destructive button is the solid `danger` variant, and focus starts on Cancel.

### 4.3 Reading and content
For the Reading / content surface (§10): articles, posts, documentation. One `<.prose>` component (or the profile's equivalent) styles rendered content, so no page styles its own `h2` or `blockquote`.
- **Article scale** (knowledge base, Font Recommendations): body `text-lg` (18px; 16px for Merriweather), title `text-5xl` (`text-3xl` on mobile), meta `text-base` in `text-ink-subtle`. The title keeps the profile's heading weight; light titles are EX-07, Marketing only. Body `leading-relaxed`, column `max-w-prose`.
- **Headings:** more space above than below (`mt-12 mb-4` for `h2`, `mt-8 mb-3` for `h3`); weight, not size jumps, separates levels below `h2`.
- **Links** in prose: `text-brand-ink underline decoration-2 underline-offset-4`.
- **Lists:** real `ul`/`ol` with visible markers, or icon bullets (§2.6); `space-y-2`.
- **Quotes:** `blockquote` with a `border-l-4 border-brand` side or a big quote mark, text in `text-ink-muted`, attribution in a `figcaption`. Pull quotes stay rare.
- **Code:** inline `code` is `font-mono bg-sunken rounded-sm px-1`, one scale step below the body (`text-base` in 18px prose). Blocks: `font-mono text-sm bg-sunken rounded-lg p-4 overflow-x-auto`, so only the block scrolls, never the page; an optional header row with the file name or language in `text-ink-subtle`. Syntax colours come from the palette's scales, and every one passes 4.5:1 on `sunken` in both themes.
- **Images:** the cover at a fixed `aspect-video object-cover`; images in the body at `max-w-prose`, natural ratio, inside a `figure` with a `figcaption` in `text-sm text-ink-subtle`. Always `alt` (empty only if decorative).
- **People photos:** `aspect-4/5` for portraits, `aspect-square rounded-full` for avatars, `object-cover` with `ring-1 ring-inset ring-ink/10` (§2.6).
- **Share image (Open Graph):** 1200×630, built from the tokens (canvas or `hero`, brand, the display face), a short title at 60px or more, no small text, the logo once. Set `og:image` and `twitter:card` on every public page.
- **Logo and favicon:** the wordmark is an inline SVG in `currentColor` (or tokens), so it follows the theme; a monogram, redrawn for 16–32px, is the favicon and the small-size logo.

---

## 5. Component architecture

```
components/core_components.ex     primitives: button input badge card link_card alert modal table empty_state
components/layouts.ex             shell, nav, flash_group, theme_toggle
components/<domain>_components.ex domain: order_card, order_status (built from primitives)
live/<domain>_live/index.ex       page: state, events, params; markup = components + layout classes
```

- **Function components by default,** one module per domain (`<Domain>Components`), imported in `html_helpers`. Such a module does `use Phoenix.Component` and `import ForkaWeb.CoreComponents` (`use ForkaWeb, :html` would import itself).
- **Layers point down:** LiveView → domain → primitive → tokens. Primitives know no domain. Domain components map data to props (enum → tone and label, `Decimal` → "$3", date → "Jun 1, 2026"), never Repo or PubSub.
- **Primitives wrap daisyUI's classes** where they meet §6 and use the tokens for the rest (§3.5). Templates call primitives, so a restyle, an upgrade or a contrast fix happens in one place.
- **Declare everything:** `attr` with type, `default:`, `doc:`, and `values:` for every option; `slot` with its attrs. These checks are compile-time only.
- **Style via props:** `variant`, `size`, `tone`. `class` is for layout only (width, placement, `hidden`). A new look is a new variant.
- **No outer margins in components:** parents space their children with `gap-*`. Clashing classes have no reliable winner.
- **Full class names only:** Tailwind can't see `"bg-#{tone}-soft"`; map options in function clauses.
- **Pass-through:** `attr :rest, :global` on the root, with `include: ~w(form name value)` as needed.
- **Slots compose:** named regions (`<:actions>`), slot attrs (`<:col label="Price">`), `:let`, `render_slot(@title) || "Default"`.
- **State is attributes:** render `aria-current`, `aria-expanded`, `data-state`; style with `aria-[current=page]:`, `data-[state=open]:`, `group`, `peer`, `has-*`.
- **`:key`** on every non-stream `:for`.
- **LiveComponents only for state and events together** (autocomplete, wizard), never to organise code. One root tag, an `id`, `phx-target={@myself}`. Data flows down; the component reports up via `send(self(), msg)` or a callback attr. Pass only the keys it needs; batch loads in `update_many/1`.
- **Component JS is a colocated hook** (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Copy">`), the one allowed `<script>` in HEEx: it's bundled at compile time, so the CSP holds. Shared hooks go in `assets/js/`; hooks that own their DOM need `phx-update="ignore"`.

---

## 6. Recipes

The recipes set the design: props, variants, states and token classes. With daisyUI, keep the generated classes where they already match a recipe and use its token classes where they don't.

**Button** (`core_components.ex`; keeps the generated `<.link>` / `<button>` switch)
```elixir
attr :variant, :string, default: "primary", values: ~w(primary secondary link danger danger-link)
attr :size, :string, default: "md", values: ~w(sm md lg)
attr :class, :any, default: nil, doc: "layout only"
# class: ["inline-flex min-h-11 items-center justify-center gap-2 rounded-md font-semibold
#   focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-ink
#   phx-submit-loading:opacity-60", button_size(@size), button_variant(@variant), @class]

defp button_size("sm"), do: "px-3 py-1 text-sm"
defp button_size("md"), do: "px-4 py-2 text-base"
defp button_size("lg"), do: "px-6 py-3 text-lg"
defp button_variant("primary"), do: "bg-brand text-on-brand shadow-1 hover:bg-brand-strong active:shadow-none"
defp button_variant("secondary"), do: "bg-surface text-brand-ink ring-2 ring-inset ring-brand hover:bg-brand-soft"
defp button_variant("link"), do: "text-brand-ink hover:underline"
defp button_variant("danger"), do: "bg-danger text-on-danger shadow-1 hover:bg-danger-strong active:shadow-none"
defp button_variant("danger-link"), do: "text-danger-ink hover:underline"
```

**Badge**
```elixir
attr :tone, :string, default: "neutral", values: ~w(neutral brand accent success warning danger)
slot :inner_block, required: true

def badge(assigns) do
  ~H"""
  <span class={["inline-flex rounded-sm px-2 py-1 text-sm/5 font-semibold", tone(@tone)]}>
    {render_slot(@inner_block)}
  </span>
  """
end

defp tone("neutral"), do: "bg-sunken text-ink-muted"
defp tone("brand"), do: "bg-brand-soft text-brand-ink"
defp tone("accent"), do: "bg-accent-soft text-accent-ink"
defp tone("success"), do: "bg-success-soft text-success-ink"
defp tone("warning"), do: "bg-warning-soft text-warning-ink"
defp tone("danger"), do: "bg-danger-soft text-danger-ink"
```

**Card** (default: an article with its own action)
```elixir
attr :id, :string, required: true
attr :rest, :global
slot :badge
slot :title, required: true
slot :meta
slot :inner_block, doc: "description"
slot :actions

def card(assigns) do
  ~H"""
  <article id={@id} aria-labelledby={"#{@id}-title"}
    class="flex h-full flex-col gap-3 rounded-lg border border-line bg-surface p-6 shadow-2 dark:shadow-none" {@rest}>
    <div :if={@badge != []} class="flex flex-wrap gap-2">{render_slot(@badge)}</div>
    <h3 id={"#{@id}-title"} class="text-xl font-semibold text-ink">{render_slot(@title)}</h3>
    <p :if={@meta != []} class="text-sm text-ink-subtle">{render_slot(@meta)}</p>
    <div :if={@inner_block != []} class="grow text-ink-muted">{render_slot(@inner_block)}</div>
    <div :if={@actions != []} class="flex flex-wrap gap-3">{render_slot(@actions)}</div>
  </article>
  """
end
```
Buttons in `:actions` get `aria-describedby={"#{@id}-title"}` so "Continue" is announced with its title.

**Link card** (EX-06 only: image-led catalogs where opening the item is the only action)
```heex
<.link navigate={@navigate} class="group flex flex-col overflow-hidden rounded-lg bg-surface shadow-1 transition hover:shadow-2 focus-visible:outline-2 focus-visible:outline-brand-ink" {@rest}>
  <p :if={@eyebrow != []} class="bg-sunken px-4 py-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">{render_slot(@eyebrow)}</p>
  <div class="overflow-hidden">
    <img src={@image} alt={@alt} class="aspect-4/3 w-full object-cover transition duration-300 motion-safe:group-hover:scale-105" />
  </div>
  <div class="flex flex-1 flex-col gap-3 p-4">
    <h3 class="truncate font-semibold group-hover:text-brand-ink">{render_slot(@inner_block)}</h3>
    <div class="mt-auto flex items-center justify-between gap-2 text-sm text-ink-subtle">
      <span>{render_slot(@meta)}</span>
      {render_slot(@status)}
    </div>
  </div>
</.link>
```

**Domain wrapper** (domain knowledge here, styling stays in primitives)
```elixir
defmodule ForkaWeb.OrderComponents do
  use Phoenix.Component
  use ForkaWeb, :verified_routes
  import ForkaWeb.CoreComponents

  attr :status, :atom, required: true, values: [:pending, :paid, :failed, :refunded]

  def order_status(assigns) do
    ~H"<.badge tone={tone_for(@status)}>{Phoenix.Naming.humanize(@status)}</.badge>"
  end

  defp tone_for(:paid), do: "success"
  defp tone_for(:pending), do: "warning"
  defp tone_for(:failed), do: "danger"
  defp tone_for(:refunded), do: "neutral"
end
```

**Stream with an empty state** (the wrapper owns visibility, so its classes never clash with the component's)
```heex
<div id="orders" phx-update="stream" class="grid gap-6 grid-cols-[repeat(auto-fill,minmax(18rem,1fr))]">
  <div id="orders-empty" class="hidden only:block col-span-full">
    <.empty_state icon="hero-inbox">
      No orders match “{@filter["q"]}”.
      <:action><.button variant="secondary" patch={~p"/orders"}>Reset filters</.button></:action>
    </.empty_state>
  </div>
  <.order_card :for={{id, order} <- @streams.orders} id={id} order={order} />
</div>
```
`empty_state/1`: a dashed `border-2 border-dashed border-line` box, the icon in a `size-12 rounded-full bg-brand-soft text-brand-ink` circle, `text-ink-muted` copy, and an `:action` slot.

**Alert** (failed states, form-level errors)
```heex
<div role="alert" class="flex gap-3 rounded-md border-2 border-dashed border-danger bg-danger-soft p-4 text-danger-ink">
  <.icon name="hero-exclamation-triangle-mini" class="size-5 shrink-0" />
  <p>{@message} <.button :if={@retry} variant="link" phx-click={@retry}>Try again</.button></p>
</div>
```

**Timeline item**
```heex
<li class="relative flex gap-4 pb-8 before:absolute before:left-5 before:top-12 before:h-full before:border-l before:border-line">
  <span class="grid size-10 shrink-0 place-items-center rounded-full bg-sunken font-semibold tabular-nums text-ink-muted">{@marker}</span>
  <div class="min-w-0 max-w-prose">
    <p><span class="font-semibold text-ink">{@actor}</span> <span class="text-ink-subtle">{@verb}</span></p>
    <p :if={@quote} class="mt-1 italic text-ink-muted">{@quote}</p>
  </div>
</li>
```

**Milestone banner**
```heex
<div class="rounded-lg bg-hero p-6 text-center text-white">
  <p class="flex items-center justify-center gap-2 text-2xl font-semibold">
    <.icon name={@icon} class="size-6 text-hero-ink" /> {@headline}
  </p>
  <p class="mt-1 text-sm">{@tagline}</p>
</div>
```

**Contextual auth CTA**
```heex
<.button :if={@current_scope} phx-click={@action}>{@action_label}</.button>
<.button :if={!@current_scope} navigate={~p"/users/log-in?return_to=#{@current_path}"}>
  Log in to {@action_verb}
</.button>
```

**Share field** (with a colocated hook)
```heex
<div class="flex gap-2">
  <label for="share-url" class="sr-only">Share link</label>
  <input id="share-url" type="text" readonly value={@url}
    class="min-h-11 grow rounded-md bg-sunken px-3 text-ink ring-1 ring-inset ring-line-strong" />
  <.button id="share-copy" phx-hook=".Copy" data-target="share-url">Copy</.button>
</div>
<p id="share-status" aria-live="polite" class="text-sm text-ink-subtle"></p>
<script :type={Phoenix.LiveView.ColocatedHook} name=".Copy">
  export default {
    mounted() {
      this.el.addEventListener("click", async () => {
        await navigator.clipboard.writeText(document.getElementById(this.el.dataset.target).value)
        document.getElementById("share-status").textContent = "Copied!"
      })
    }
  }
</script>
```

---

## 7. LiveView behaviour

- **URL state:** filters, sort, page and tab live in params. The form's `phx-change` → `push_patch(to: ~p"/items?#{params}")`; `handle_params/3` loads and re-streams with `reset: true`.
- **Collections:** streams, a separate count assign, and the `hidden only:block` empty state.
- **Async:** `assign_async/3` with `<.async_result>`: `:loading` shows a content-sized skeleton, `:failed` an alert with Retry. Instant feedback with `phx-disable-with="Saving…"` and the `phx-*-loading:` variants.
- **Forms:** `to_form` with `<.input>`, `phx-change` validation, `phx-debounce="blur"` on text inputs. Errors show only after the user has touched the field (`used_input?/1`, built into 1.8's `<.input>`) and say how to fix.
- **One `<.modal>`** (Phoenix 1.8 no longer generates one), opened and closed with JS commands, `<.focus_wrap>`, close on Esc and backdrop, `<.portal>` if an ancestor clips it. Full-screen with stacked buttons below `sm`.
- **Removals:** fade out via the generated `hide/2`.
- **Navigation:** `navigate` between LiveViews, `patch` within one. Every page sets `:page_title`.

---

## 8. Avoid

| Anti-pattern | Do instead |
|---|---|
| Copying a component's markup to change its look | Add a variant |
| Raw daisyUI classes in templates, its default themes, derived colours that fail contrast | Primitives that wrap it, themes filled from the scales, token pairs |
| Tailwind palette classes (`bg-gray-500`, `text-red-600`) | Semantic tokens |
| Hex values, arbitrary values (`[13px]`), off-scale spacing, `@apply`, page CSS | Tokens and scale steps only |
| Muted text via opacity (`text-ink/70`) | `text-ink-muted` / `text-ink-subtle` (EX-09 is the one exception) |
| Interpolated class names (`"bg-#{tone}-soft"`) | Function clauses returning full class names |
| Outer margins inside components | `gap-*` on the parent |
| Emoji in UI copy, badges or buttons | Inline SVG icons in `currentColor` with `aria-hidden` (EX-03 is the exception) |
| Generator leftovers ("Listing X", "· Phoenix Framework", demo buttons) | Real headings, `<.live_title>` without the default suffix, delete demo code |
| Unlabelled numbers | A label or unit ("P1 · High", "3 nights", "$12") |
| Destructive actions styled like safe ones; `data-confirm`; irreversible actions with no confirmation | `danger-link` and a modal naming the object |
| Lists with no empty, loading or failed state | All three, designed (§4.1) |
| Non-responsive nav, horizontal overflow | Menu button below `md`, test at 375px |
| Dark mode without adapting assets | `currentColor` SVGs, transparent illustrations, `dark:shadow-none` |
| Unstyled third-party widgets (date pickers, editors) | Theme them with the tokens; show disabled options visibly |
| Selections with no visual feedback | Hover, selected and focus states; show the selection as text too |
| Ambiguous data (dates without a year, blank "any" inputs) | "Jun 1, 2026"; a visible "Any" placeholder |
| Raw enums and technical copy (`upcoming`, "can't be blank") | Human labels and messages that say how to fix |
| Implementation fields in forms ("Image path" text box) | An upload or picker with a preview |
| Losing context after login | `return_to` and redirect back |
| Icon-only controls without labels; images without `alt` | `aria-label`; `alt` from the entity name (or `alt=""` if decorative) |
| Layout shift (scrollbar, validation messages) | `scrollbar-gutter: stable`, reserved error space |
| Several competing accents | One brand colour, one warm accent, fixed status colours |
| Font CDNs | Self-hosted fonts in `priv/static/fonts` |
| A data grid inside `max-w-*`, its detail panel as a floating card | The Workspace archetype (§1, §13.1) |
| A full input box on every row of a grid; mono for money | Inline value inputs (§13.3); the UI font with `tabular-nums` |
| Status colour on every row, "complete" bars repeated per row | Colour only where action is needed; resolved = neutral (§13.4, §13.7) |
| Number fields that reject `1.234,56` or `100 + 50` | One forgiving parser per value type (§14.1) |
| Disabled via `opacity` alone; native file inputs showing | `bg-sunken text-ink-subtle` with the reason; the app's own button (§13.8) |

---

## 9. Pre-ship checklist

- [ ] One primary element and one primary action per screen.
- [ ] Every list has a **count**, an **empty state** and **loading/failed** states; filters live in the **URL** with a **Reset**.
- [ ] Status uses **`<.badge>` through a domain wrapper** with human labels; units, currencies and years present.
- [ ] Destructive or irreversible actions use `danger-link` and are **confirmed in a modal** that names the object.
- [ ] Gated actions show a **contextual CTA** and **return the user** after login.
- [ ] Three ink colours, the profile's weights; **contrast passes in both themes**; colour is never the only signal.
- [ ] Nav **collapses below `md`**; no horizontal scroll at **375px**; touch targets **44px or more**; the key interactive area fits the viewport.
- [ ] **Light, Dark and System checked:** logo, illustrations, widgets and focus rings adapt; no flash on load.
- [ ] `scrollbar-gutter: stable`; validation messages **don't shift** the layout.
- [ ] Icon-only buttons have **`aria-label`**; images have **`alt`**; async results are announced (`aria-live`); motion respects `prefers-reduced-motion`.
- [ ] No **generator defaults** or demo buttons; one **casing rule** (sentence case).
- [ ] At most **two moments of delight** per screen.
- [ ] The screen's **archetype** is recorded; a Workspace fills the viewport, has one primary metric and an inspector with its three states (§13).
- [ ] Number fields accept **locale formats and arithmetic**; reversible actions offer **Undo**; the grid works from the **keyboard** (§14).
- [ ] **Screenshots at 1440px and 375px in both themes** passed the squint test and the counts (§13.9).
- [ ] Every **exception** in use is enabled in the profile and named in the component's `@doc` (§11).
- [ ] After a palette or token change, `elixir check_contrast.exs assets/css/app.css` (from the `phoenix-ui` skill's `scripts/`) passes every §3.2 pair in both themes.
- [ ] These commands print nothing:

```bash
grep -rnE '\b-?(p[xytrbl]?|m[xytrbl]?|gap(-[xy])?|space-[xy])-([0-9]\.5|5|7|9|10|11|14|20|28|36|40)\b' lib/
grep -rnE '\[[0-9.]+(px|rem|em)\]|#[0-9a-fA-F]{6}\b|@apply|data-confirm' lib/ assets/css/
grep -rnE '(bg|text|border|ring)-[a-z-]*#\{' lib/
grep -rnE '\b(bg|text|border|ring|from|to|fill|stroke)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]{2,3}\b' lib/
```

Outside Phoenix, replace `lib/` with the source folder (`app/`, `src/`) and `assets/css/` with the stylesheet folder. The second command also matches the `@font-face` and `--color-*` lines in `app.css` if they use hex; keep them in HSL so it stays quiet. Arbitrary values that are tokens (`w-(--pct)`, `grid-cols-[repeat(...)]`) don't match.
