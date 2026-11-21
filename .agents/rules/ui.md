---
trigger: always_on
description: UI directives for any Phoenix LiveView + Tailwind v4 app, §0–§2 and the map of the other ui-*.md files. App-specific choices live in ui-profile.md
---

# UI Directives: Phoenix LiveView + Tailwind v4

Read these before you write or review a template, a component or `app.css`. Antigravity truncates a rule file past 24,000 bytes, so they are split into six always-on files, and the section numbers run across them:

| File | Sections |
|---|---|
| `ui.md` | Quick rules, §0 How to decide, §1 Process, §2 Design foundations |
| `ui-tokens.md` | §3 Tokens: scales, semantic tokens, the `app.css` template, theme switching, daisyUI |
| `ui-components.md` | §4 Product patterns, §5 Component architecture, §6 Recipes, §7 LiveView behaviour, §8 Avoid, §9 Pre-ship checklist |
| `ui-surfaces.md` | §10 Surfaces, §11 Scoped exceptions, §12 App profile |
| `ui-data.md` | §13 Workspace screens: data grids, inline values, status pills, the inspector, dark mode on dense screens, the visual review |
| `ui-interaction.md` | §14 Interaction: forgiving input (arithmetic in number fields), smart defaults, undo, keyboard, comboboxes, actions on the data |

## Quick rules

The whole system in twelve lines. In a hurry, apply these; the sections below say why and how.

1. **Pick the layout archetype first** (§1): Page, Form, Reading or Workspace. A Workspace (grid, ledger, board) fills the viewport; the others are centred and capped.
2. **One primary element and one primary action** per screen, with a state and the action that resolves it.
3. **Colour is a budget** (§2.4): it marks what needs action; the resolved state is neutral. One brand colour, one warm accent, fixed status colours.
4. **Three text levels that stay apart in both themes** (§2.1); never grey text on coloured fills.
5. **Three backgrounds at most** (`canvas`, `surface`, `sunken`), visibly different, and the brand fill at 3:1 or more against them in both themes.
6. **Semantic tokens only**: no palette classes, hex, arbitrary values or off-scale steps.
7. **Space separates first,** then a background step, then a shadow; a border comes last.
8. **Numbers:** a proportional font with `tabular-nums`, right-aligned, with units and currency.
9. **Editable values in a grid look like text until hover or focus** (§13.3); full input boxes belong to forms.
10. **Number fields accept what people type** (`1,234.56` or `1.234,56`, `$50`, `100 + 50`) and show the result (§14.1).
11. **Reversible → do it and offer Undo; irreversible → confirm** naming the consequence (§14.3).
12. **Before "done":** `check_contrast.exs`, the §9 greps, and a screenshot at 1440px and 375px in both themes (§13.9).

Reference files in `.agents/shared/` aren't always-on. Open them when the task needs them:

| File | Read it when |
|---|---|
| `ui-palettes.md` | Picking or swapping the app's palette (Appendix A, all scales in hex) |
| `ui-daisyui.md` | Touching `app.css` or a primitive while the app keeps daisyUI, the default (§3.5) |
| `ui-knowledge-base.md` | A design question the rules don't settle: exact scales, font recommendations, the component variant menu |

- **Stack:** Phoenix 1.8, LiveView 1.1+, Tailwind v4, Heroicons. daisyUI 5, kept by default and wrapped in primitives (§3.5).
- **Precedence:** current best practice comes **first**. Refactoring UI and its companion PDFs (Color Palettes, Font Recommendations, Component Gallery, 2018) are the foundation for every principle they cover; where current, well-supported practice has moved past them (fluid display type, OKLCH, the font picks), these directives say so and the newer practice wins. A newer technique enters only through these directives, and only if it keeps the fundamentals: WCAG 2.2 AA, contrast in both themes, a systematic scale, mobile first. Patterns from other sources (Pragmatic Studio, house rules) fill gaps. These files then settle component and UI-behaviour questions. The Phoenix, LiveView and Tailwind docs settle anything they don't cover. The project's other Phoenix rules (`AGENTS.md`, `.agents/rules/`) still apply, except phx.new's "write your own components instead of using daisyUI", which §3.5 replaces.
- **App profile:** each app keeps its own choices in `ui-profile.md` next to these files (§12): palette, fonts, weights, radii, token overrides, daisyUI kept or removed, surfaces, enabled exceptions and domain notes. **The profile wins over the defaults here**; anything it doesn't mention follows these files.
- **Outside Phoenix:** §0–§2, the scale and semantic token names (§3.1–§3.2), §4, §8–§11 and the profile don't depend on the stack. A non-Phoenix app (Nuxt, plain CSS) declares the same `--color-*` variables in `:root` with `light-dark()` instead of `@theme`, builds its own `button`, `badge`, `card` and so on with the same variants and props as §5–§6, and runs the §9 greps on its own source folder.
- **Sources:** the design rules come from Refactoring UI and its Color Palettes, Font Recommendations and Component Gallery. The product patterns come from a review of Pragmatic Studio's Phoenix course apps. Where those conflict, the conflict became a scoped exception (§11).

---

## 0. How to decide

Stop at the first answer.

1. **A component exists:** use it. Need a new look? Add a variant. Never copy its markup.
2. **A token exists:** use it. No hex, no arbitrary values (`[13px]`), no off-scale steps.
3. **Something doesn't stand out:** soften its neighbours first. Weight and colour before size.
4. **Picking a value:** guess the middle step, compare it with its neighbours, keep the clear winner.
5. **Still unsure:** more space, fewer borders, less colour, shorter copy.

---

## 1. Process

- **Start with one real feature** ("search orders"), not the shell. Navigation emerges later.
- **Pick one layout archetype per screen** before the first line of markup, and record it in the profile (§12.8). The archetype sets the width, the skeleton and which rules apply:

  | Archetype | Screens | Width | Skeleton |
  |---|---|---|---|
  | **Page** | lists, detail pages, settings | `max-w-5xl` centred | header → filters → cards (§4) |
  | **Form** | create, edit, wizards | `max-w-md` to `max-w-2xl` | one column of fields (§4.12, §7) |
  | **Reading** | articles, docs | `max-w-prose` | §4.3 |
  | **Workspace** | data grids, ledgers, boards, calendars, planners | **full width and height** | sidebar `w-64` · main `flex-1 min-w-0` (only it scrolls) · inspector `w-80` (§13) |

  A Workspace that gets a Page skeleton is the most common layout bug: a dense grid squeezed into `max-w-*` with dead space beside it, its detail panel floating as a card.
- **Sketch in greyscale** so spacing, contrast and size do the work. Colour comes last; typeface, shadows and icons come once the layout works.
- **Be a pessimist:** ship the smallest useful version and don't imply features you won't build. Iterate: design, build, use, fix.
- **Design every state:** empty, loading, failed, one item, 2,000 items, long names.
- **Pick one personality** and record it in the profile:
  - **Font:** serif = elegant or classic; rounded sans = playful; neutral sans = plain, lets other elements carry it.
  - **Colour:** blue = safe and familiar; gold = expensive; pink = fun.
  - **Radius:** none = serious; small = neutral; large = playful. **Never mix square and rounded corners.**
  - **Voice:** impersonal = official; casual = friendly.
- **Systematise everything:** size, weight, line height, colour, spacing, width, shadow, radius, border width, opacity. Pick from the system, never ad hoc.

---

## 2. Design foundations

### 2.1 Hierarchy
- **One primary element and one primary action per screen.** Everything else supports them.
- **Weight and colour before size.** Bolder text at a sane size beats huge text; softer secondary text beats tiny text.
- **Three ink colours, two weights:** `text-ink`, `text-ink-muted`, `text-ink-subtle`; `font-normal` (400) and `font-semibold` (600), plus what the profile adds. Never below 400 in UI text.
- **The three levels stay apart in both themes:** each level's contrast on `surface` is at least 1.2× the next one's (`ink` ≈ 10:1 or more, `ink-muted` ≈ 7–9:1, `ink-subtle` ≈ 4.5–6:1). Dark mode is where they collapse (grey-50, 100 and 200 on grey-800 all read the same), so the dark mapping in §3.2 jumps a step and `check_contrast.exs` measures the gaps.
- **On coloured backgrounds, never grey or white-with-opacity text:** use that hue's `*-ink` or `on-*` token.
- **Emphasise by de-emphasising:** soften inactive nav items; drop a competing sidebar's background.
- **Labels are a last resort:** let the format speak (`$19.99`), merge label and value ("12 left in stock"). Needed labels are smaller and lighter than the value, unless users scan for them (spec sheets).
- **Heading tags carry meaning, classes carry hierarchy:** an `<h1>` can be `text-lg`. Section titles often act as labels: small, muted, sometimes `sr-only`.
- **Balance weight and contrast:** soften solid icons beside text; widen faint borders (`border-2`) instead of darkening them.
- **Actions form a pyramid:** primary = solid `brand`, secondary = outline, tertiary = link.
- **Destructive isn't automatically big and red:** `danger-link` on the page, solid `danger` only in the confirmation step. Never style Delete like Edit.

### 2.2 Layout and spacing
- **Spacing steps:** `1 2 3 4 6 8 12 16 24 32 48 64 96` (4–384px). Neighbours differ by at least 25%; `.5` steps and `5 7 9 10 11 14 20 …` are off-scale.
- **Start with too much white space,** then remove it. Dense screens (admin, dashboards) are a choice, not a default.
- **More space around a group than inside it:** a label sits nearer its input than the field above; headings get more space above than below.
- **Don't fill the screen** on Page, Form and Reading: forms `max-w-md`, prose `max-w-prose`, app pages `max-w-5xl` with `px-4 sm:px-6`. Spare width becomes columns, not stretch. **A Workspace fills it:** the grid takes every pixel between the sidebar and the inspector, never a centred `max-w-*` (§13.1).
- **Naturally sized things get fixed widths** (sidebar `w-64`, modals, cards); the main area flexes (`w-full max-w-*`), never percentage columns.
- **Mobile first at about 400px** with unprefixed classes; `sm:` / `md:` fix only what felt compromised. Big things shrink faster (`text-5xl` → `text-2xl` on mobile). Button padding isn't proportional: large gets roomier, small tighter.
- **Components used in wide and narrow slots query their container** (`@container`, `@md:`), not the viewport.
- **Card grids:** `grid gap-6 grid-cols-[repeat(auto-fill,minmax(18rem,1fr))]` (one column on phones).
- **Detail pages:** a 1/3 + 2/3 split (`md:grid-cols-3`, content in `md:col-span-2`); related items stack under the content on mobile.
- **One header row:** logo on the left; main nav, then utility controls (theme, account) at the right end of the same row. Never a second header row just for utilities; below `md`, nav and account move into the menu.
- **No horizontal scroll at 375px;** the nav collapses below `md`; boards and calendars fit the viewport (`min(70vh, 90vw)`).
- **Reserve a line under each field** for its error, so the layout doesn't shift.
- **Touch targets of at least 44×44px** (`min-h-11`).

### 2.3 Typography
- **Type scale:** `text-xs` to `text-7xl` (12, 14, 16, 18, 20, 24, 30, 36, 48, 60, 72px). Never `em`, never arbitrary sizes.
- **Fluid display type:** big headings may scale smoothly with `text-display` (§3.3: `clamp(3rem, 1.5rem + 4vw, 4.5rem)`, 48→72px), or with more `--text-display-*` tokens the profile adds. Each clamps between two scale steps and mixes `rem` with `vw`, never `vw` alone, so browser zoom still works (WCAG 1.4.4). Only for headings at `text-4xl` or larger; body and UI text stay fixed. Breakpoint steps (`text-3xl md:text-6xl`) stay fine.
- **Wrapping:** `text-balance` on headings, `text-pretty` on paragraphs, so lines don't end with a lone word.
- **Fonts** are chosen in the profile. The picks below are proven starting points, not a closed list:
  - **App UI (one family):** Source Sans 3 (the template default), IBM Plex Sans, Public Sans, Figtree, Atkinson Hyperlegible (strongest legibility). A sans with 5+ weights and italics, a tall x-height, not condensed; variable fonts preferred (one file, every weight). Inter and Roboto are sound too; they read as the default look, so pair them with another strong signature. Unsure: the system stack.
  - **Reading-heavy apps:** Merriweather (body 16px) with Merriweather Sans, Source Serif 4 with Source Sans 3, or Source Sans 3 at 18px body.
  - **Display headings (optional):** a heavier cut of the UI family, a characterful grotesque (Bricolage Grotesque) or a serif for personality (Fraunces; Instrument Serif at 48px or more, since it has one weight). Display headings usually need 700 or heavier: the profile adds `--font-weight-bold: 700` (or `-black: 900`) for them, which is the expected case, not an exception. Body and UI text stay at 400 / 600.
  - **Code:** JetBrains Mono or IBM Plex Mono as `--font-mono` (a clear `0`/`O` and `1`/`l`), or the system mono stack.
  - **Personality:** a neutral UI family is plain on purpose (§1); give the app a signature elsewhere (palette, display face, motif).
  - **Search beyond the list** when the personality asks for something specific (a brand, a genre, an era): propose two or three candidates from Google Fonts, Fontsource, Fontshare or Velvetyne, ideally shown side by side. Filter for an open licence (OFL or Apache) that allows self-hosting, Latin Extended (accents: "ação", "pôr"), 5+ weights with italics for UI text (a display face may have fewer), and a variable version when there is one. Check legibility at 14–16px and the digits before choosing; the profile records the pick and why.
  - **Self-host** them in `priv/static/fonts` with `@font-face` in `app.css`; the default CSP rules out font CDNs.
- **Body text 16–18px**, at least 16px on mobile. Paragraphs stay at 45–75 characters (`max-w-prose`), even in wide layouts.
- **Line height falls as size grows and rises with width:** defaults for UI, `leading-relaxed` for wide prose, `leading-tight` for big headings.
- **Align mixed sizes on the baseline** (`items-baseline`).
- **Left-align.** Centre only headlines and blocks of three lines or fewer; if longer, rewrite shorter. Right-align numbers in tables; `tabular-nums` on numbers that change live.
- **`tracking-tight`** on big headings in wide fonts; **`uppercase tracking-wide` only for small eyebrow labels.** Badges, buttons and everything else use sentence case ("Log in to continue").
- **Links:** in prose, colour + underline; in link-heavy UI, weight or `text-ink` with colour on hover; ancillary links, hover only.

### 2.4 Colour
- **One palette per app,** from the Refactoring UI palettes (Appendix A), recorded in the profile. Each scale has 10 shades: 900 darkest, 50 lightest.
- **OKLCH for new scales, HSL accepted,** declared once in `@theme`. Never hex in templates or CSS, and no runtime shades. OKLCH lightness is perceptual, so equal `L` steps look equally spaced across hues, and the same step of two scales has about the same contrast. Scales copied from Appendix A may stay in HSL.
- **Templates use semantic tokens** (§3.2). Numbered shades appear in templates only for categories, charts and illustrations.
- **One brand colour** for primary actions, links and focus; **one warm accent** for delight. **Fixed status colours:** success = open/ok, warning = pending, danger = error/destructive, neutral (`sunken`) = closed/draft.
- **Colour is a budget.** On a data screen colour marks what needs action; the resolved state (zero, done, on track) is neutral text with no fill. If more than about a fifth of the rows carry a status colour, the mapping is wrong. Each coloured value also carries an icon or a word, since colour alone fails for a tenth of users (§13.4).
- **Fills stand out from their background:** `brand` and `danger` fills measure at least 3:1 against `surface` and `canvas` in both themes (WCAG 1.4.11). On dark backgrounds that means a *light* fill with dark text (`brand-300` with `on-brand` = grey-900), not the light theme's saturated fill, which sinks into the surface at about 2:1.
- **Dark neutrals carry little colour:** the dark `grey-700`–`900` steps keep OKLCH chroma at about 0.03 or less (HSL saturation around 20% or less). A tinted grey that looks refined in light mode turns every dark surface, input and button into one navy block. `check_contrast.exs` reports the chroma; a palette that exceeds it desaturates its dark steps in the profile.
- **Contrast:** at least 4.5:1 for text under about 18px, 3:1 for large text and control borders, **in both themes**.
- **Flip contrast:** dark text on a soft tint (`bg-success-soft text-success-ink`) beats white on a saturated fill, unless the element is the focus.
- **Never colour alone:** add an icon or a label. Charts vary lightness, not only hue.
- **Greys carry temperature** (a touch of blue or yellow); no pure black.
- **A brand that already has its own colour:** build a 10-shade scale from it with the steps below instead of forcing the nearest palette, record it in the profile and check every §3.2 pair.
- **New shades:** 500 = button fill, 900 = text, 50 = tint; fill 700 and 300, then the rest. In OKLCH, step `L` from about 0.97 (50) to 0.25 (900), keep the hue steady (shift yellows toward orange as they darken), and lower chroma at the ends so every shade stays in the sRGB gamut. In HSL, saturate shades far from 50% lightness; to lighten, rotate hue toward 60°/180°/300°, to darken toward 0°/120°/240°, 20–30° at most.
- **Dark mode is hand-picked** through `light-dark()`, never an inversion.

### 2.5 Depth
- **Light comes from above.** Raised: a lighter 1px top edge (a hand-picked shade, never white with opacity) and a small, sharp shadow below. Inset (inputs, wells): `inset-shadow-xs` and a lighter bottom lip.
- **Elevation by z-position:** `shadow-1` buttons, `shadow-2` cards, `shadow-3` dropdowns and popovers, `shadow-4` dragged items and floating panels, `shadow-5` modals. Lift on drag; drop on press (`active:shadow-none`).
- **Two-part, soft shadows:** each level pairs a tight contact shadow with a larger, softer one, tinted with the palette's darkest grey (Refactoring UI, "Use two shadows"). The book's single-shadow numbers (`0 4px 6px` at 20% black) are a starting point; keep the levels, soften the look to fit the personality.
- **Flat depth:** lighter than the background reads raised, darker reads inset. Overlap layers: a card crossing two sections, avatars with `ring-2 ring-surface`.
- **Fewer borders:** separate with space first, then a background change (`bg-sunken`), then a shadow. A border comes last, never all three.
- **Dark mode:** raised surfaces get lighter; separate with surface steps and `border-line`, since shadows fade (`dark:shadow-none`). Three backgrounds at most on one screen (`canvas`, `surface`, `sunken`), each visibly apart from its neighbour; `check_contrast.exs` prints their separation.

### 2.6 Images, icons and finishing touches
- **Good images only,** never placeholders "for now". Text on photos needs an overlay, a colourised image or a no-offset glow `text-shadow`.
- **User images:** a fixed box (`aspect-4/3 object-cover`) with `ring-1 ring-inset ring-ink/10` instead of a border.
- **Icons at their intended size:** `-micro` `size-4`, `-mini` `size-5`, outline/solid `size-6`. To fill space, put the icon in a shape (`size-12 rounded-full bg-brand-soft`). Redraw the favicon at 16px; crop screenshots, never shrink them.
- **Supercharge defaults:** icon bullets, big quote marks, `accent-brand` form controls, custom underlines (`decoration-2 underline-offset-4`).
- **Add colour without illustration:** accent borders (card tops, active nav, alert sides), a section background change, a gradient of hues at most 30° apart, a faint `currentColor` pattern at 5% opacity or less.
- **Think outside the box:** dropdowns with sections and columns, tables merging related columns, selectable cards instead of radios (`has-checked:ring-brand`).
- **Pick one variant per component** (button, input, badge, tabs, alert, modal, card…) and record it in the profile, so every screen uses the same one.
