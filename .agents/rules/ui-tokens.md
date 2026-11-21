---
trigger: always_on
description: UI directives §3: scales, semantic tokens, the app.css template, theme switching and daisyUI
---

# UI Directives: tokens and `app.css`

Part of the UI directives; start at `ui.md`. The app's `ui-profile.md` wins over these defaults.

## 3. Tokens: `assets/css/app.css`

`app.css` holds only tokens, variants, `@font-face` and base rules (plus daisyUI's two theme blocks, §3.5). Never `@apply` or page CSS (`.orders-index .card`).

### 3.1 Scales

Every app defines the same scale names, filled from its palette:

| Scale | Filled from |
|---|---|
| `grey-50 … grey-900` | The palette's neutral scale |
| `brand-50 … brand-900` | The palette's primary scale |
| `accent-50 … accent-900` | The palette's warm supporting scale (yellow or amber) |
| `success-*` | Green, or Teal if the palette has no green |
| `warning-*` | Usually aliases `accent-*` |
| `danger-*` | Red (or Red Vivid) |

### 3.2 Semantic tokens

Templates use only these.

| Token | Role | Light | Dark |
|---|---|---|---|
| `canvas` | Page background | grey-50 | grey-900 |
| `surface` | Cards, header, dialogs | white | grey-800 |
| `sunken` | Wells, inputs, neutral chips, eyebrow strips | grey-100 | grey-900 |
| `line` | Borders and dividers | grey-200 | grey-700 |
| `line-strong` | Control borders (3:1) | grey-500 | grey-300 |
| `ink` | Main text, headings | grey-900 | white |
| `ink-muted` | Secondary text, descriptions | grey-700 | grey-100 |
| `ink-subtle` | Meta, helper text | grey-600 | grey-200 |
| `brand` / `on-brand` | Primary button fill / text on it | brand-600 / white | brand-300 / grey-900 |
| `brand-strong` | `brand` hover | brand-700 | brand-200 |
| `brand-ink` | Links, outline buttons, active nav, focus ring | brand-600 | brand-200 |
| `brand-soft` | Tinted backgrounds, active nav, icon circles | brand-50 | brand-900 |
| `hero` / `hero-ink` | Feature bands, banners / icons on them | brand-900 / accent-400 | brand-800 / brand-100 |
| `accent-soft` / `accent-ink` | Warm highlight ("new", "featured") | accent-100 / accent-900 | accent-900 / accent-200 |
| `success-soft` / `success-ink` | Positive states | success-50 / success-800 | success-900 / success-300 |
| `warning-soft` / `warning-ink` | Pending, needs attention | warning-50 / warning-800 | warning-900 / warning-300 |
| `danger` / `on-danger` | Destructive fill / text on it | danger-600 / white | danger-200 / grey-900 |
| `danger-strong` | `danger` hover | danger-700 | danger-100 |
| `danger-soft` / `danger-ink` | Error backgrounds / error text | danger-50 / danger-700 | danger-900 / danger-200 |

**Dark fills are light.** A saturated `brand-500` or `danger-500` on `grey-800` measures about 2:1 and the button sinks into its card; a light step (`brand-300`, `danger-200`) with grey-900 text clears 3:1 against `surface` and `canvas` and 4.5:1 for its label (§2.4). Hover goes one step lighter. **Dark text jumps a step:** `ink` is white so the three text levels stay about 1.2× apart (§2.1); grey-50 / 100 / 200 on grey-800 read as one colour.

This mapping passes with the default palette below (lowest text pair: `on-brand` on `brand` in dark mode, 4.9:1; lowest fill: `brand` on `surface` in dark mode, 3.5:1 against a 3:1 target). **Palettes differ, so check every pair in both themes after swapping one** and shift by one shade where needed. The profile records every override.

### 3.3 Template

```css
/* Keep Phoenix's @import/@source lines, the heroicons @plugin, the daisyUI
   @plugin (its themes filled per §3.5), the phx-*-loading variants and the
   [data-phx-session] rule. Replace the dark variant with this
   three-state one (System, or forced by data-theme): */
@custom-variant dark {
  &:where([data-theme=dark], [data-theme=dark] *) { @slot; }
  @media (prefers-color-scheme: dark) {
    &:where(:not([data-theme=light], [data-theme=light] *)) { @slot; }
  }
}

/* @font-face blocks for the profile's self-hosted fonts go here */

@theme {
  /* Fonts, weights, radii: replace with the profile's values */
  --font-sans: "Source Sans 3", ui-sans-serif, system-ui, sans-serif;
  /* --font-display: optional, from the profile */
  --text-8xl: initial;
  --text-9xl: initial;
  /* Fluid display headings (§2.3): 48px → 72px, rem + vw so zoom still works */
  --text-display: clamp(3rem, 1.5rem + 4vw, 4.5rem);
  --text-display--line-height: 1.1;
  --font-weight-*: initial;
  --font-weight-normal: 400;
  --font-weight-semibold: 600;
  /* the profile may add --font-weight-light / -bold / -black */

  --radius-*: initial;
  --radius-sm: 0.25rem; /* badges */
  --radius-md: 0.5rem;  /* buttons, inputs */
  --radius-lg: 0.75rem; /* cards, modals */

  /* Elevation: Refactoring UI's five z-levels, drawn as its two-part shadows
     (a tight, darker contact shadow + a soft, larger one), tinted with the
     palette's darkest grey instead of black and kept soft. */
  --shadow-*: initial;
  --shadow-1: 0 1px 2px color-mix(in srgb, var(--color-grey-900) 10%, transparent), 0 1px 3px color-mix(in srgb, var(--color-grey-900) 6%, transparent);
  --shadow-2: 0 1px 3px color-mix(in srgb, var(--color-grey-900) 8%, transparent), 0 8px 24px color-mix(in srgb, var(--color-grey-900) 6%, transparent);
  --shadow-3: 0 2px 6px color-mix(in srgb, var(--color-grey-900) 8%, transparent), 0 12px 32px color-mix(in srgb, var(--color-grey-900) 10%, transparent);
  --shadow-4: 0 4px 8px color-mix(in srgb, var(--color-grey-900) 8%, transparent), 0 20px 40px color-mix(in srgb, var(--color-grey-900) 12%, transparent);
  --shadow-5: 0 8px 16px color-mix(in srgb, var(--color-grey-900) 10%, transparent), 0 32px 64px color-mix(in srgb, var(--color-grey-900) 16%, transparent);

  /* Lock the palette. Only once daisyUI is removed (§3.5); while it stays, delete this line. */
  --color-*: initial;
  --color-white: hsl(0 0% 100%);

  /* Default palette: Refactoring UI palette 10 (Cool Grey, Indigo, Yellow Vivid,
     Teal, Red Vivid). Replace with the profile's scales. */
  --color-grey-50: hsl(216 33% 97%);
  --color-grey-100: hsl(214 15% 91%);
  --color-grey-200: hsl(210 16% 82%);
  --color-grey-300: hsl(211 13% 65%);
  --color-grey-400: hsl(211 10% 53%);
  --color-grey-500: hsl(211 12% 43%);
  --color-grey-600: hsl(209 14% 37%);
  --color-grey-700: hsl(209 18% 30%);
  --color-grey-800: hsl(209 20% 25%);
  --color-grey-900: hsl(210 24% 16%);

  --color-brand-50: hsl(221 68% 93%);
  --color-brand-100: hsl(221 78% 86%);
  --color-brand-200: hsl(224 67% 76%);
  --color-brand-300: hsl(225 57% 67%);
  --color-brand-400: hsl(227 50% 59%);
  --color-brand-500: hsl(227 42% 51%);
  --color-brand-600: hsl(228 45% 45%);
  --color-brand-700: hsl(230 49% 41%);
  --color-brand-800: hsl(232 51% 36%);
  --color-brand-900: hsl(234 62% 26%);

  --color-accent-50: hsl(49 100% 96%);
  --color-accent-100: hsl(48 100% 88%);
  --color-accent-200: hsl(48 95% 76%);
  --color-accent-300: hsl(48 94% 68%);
  --color-accent-400: hsl(44 92% 63%);
  --color-accent-500: hsl(42 87% 55%);
  --color-accent-600: hsl(36 77% 49%);
  --color-accent-700: hsl(29 80% 44%);
  --color-accent-800: hsl(22 82% 39%);
  --color-accent-900: hsl(15 86% 30%);
  --color-warning-50: var(--color-accent-50);
  --color-warning-300: var(--color-accent-300);
  --color-warning-500: var(--color-accent-500);
  --color-warning-800: var(--color-accent-800);
  --color-warning-900: var(--color-accent-900);

  --color-success-50: hsl(152 68% 96%);
  --color-success-100: hsl(154 75% 87%);
  --color-success-200: hsl(156 73% 74%);
  --color-success-300: hsl(158 58% 62%);
  --color-success-400: hsl(160 51% 49%);
  --color-success-500: hsl(162 63% 41%);
  --color-success-600: hsl(164 71% 34%);
  --color-success-700: hsl(166 72% 28%);
  --color-success-800: hsl(168 80% 23%);
  --color-success-900: hsl(170 97% 15%);

  --color-danger-50: hsl(0 100% 95%);
  --color-danger-100: hsl(0 100% 87%);
  --color-danger-200: hsl(0 100% 80%);
  --color-danger-300: hsl(0 91% 69%);
  --color-danger-400: hsl(0 83% 62%);
  --color-danger-500: hsl(356 75% 53%);
  --color-danger-600: hsl(354 85% 44%);
  --color-danger-700: hsl(352 90% 35%);
  --color-danger-800: hsl(350 94% 28%);
  --color-danger-900: hsl(348 94% 20%);

  /* Semantic tokens: light-dark(light, dark). Templates use these. */
  --color-canvas: light-dark(var(--color-grey-50), var(--color-grey-900));
  --color-surface: light-dark(var(--color-white), var(--color-grey-800));
  --color-sunken: light-dark(var(--color-grey-100), var(--color-grey-900));
  --color-line: light-dark(var(--color-grey-200), var(--color-grey-700));
  --color-line-strong: light-dark(var(--color-grey-500), var(--color-grey-300));
  --color-ink: light-dark(var(--color-grey-900), var(--color-white));
  --color-ink-muted: light-dark(var(--color-grey-700), var(--color-grey-100));
  --color-ink-subtle: light-dark(var(--color-grey-600), var(--color-grey-200));
  --color-brand: light-dark(var(--color-brand-600), var(--color-brand-300));
  --color-on-brand: light-dark(var(--color-white), var(--color-grey-900));
  --color-brand-strong: light-dark(var(--color-brand-700), var(--color-brand-200));
  --color-brand-ink: light-dark(var(--color-brand-600), var(--color-brand-200));
  --color-brand-soft: light-dark(var(--color-brand-50), var(--color-brand-900));
  --color-hero: light-dark(var(--color-brand-900), var(--color-brand-800));
  --color-hero-ink: light-dark(var(--color-accent-400), var(--color-brand-100));
  --color-accent-soft: light-dark(var(--color-accent-100), var(--color-accent-900));
  --color-accent-ink: light-dark(var(--color-accent-900), var(--color-accent-200));
  --color-success-soft: light-dark(var(--color-success-50), var(--color-success-900));
  --color-success-ink: light-dark(var(--color-success-800), var(--color-success-300));
  --color-warning-soft: light-dark(var(--color-warning-50), var(--color-warning-900));
  --color-warning-ink: light-dark(var(--color-warning-800), var(--color-warning-300));
  --color-danger: light-dark(var(--color-danger-600), var(--color-danger-200));
  --color-on-danger: light-dark(var(--color-white), var(--color-grey-900));
  --color-danger-strong: light-dark(var(--color-danger-700), var(--color-danger-100));
  --color-danger-soft: light-dark(var(--color-danger-50), var(--color-danger-900));
  --color-danger-ink: light-dark(var(--color-danger-700), var(--color-danger-200));
}

/* light-dark() follows color-scheme. With daisyUI, its themes also set it. */
:root { color-scheme: light dark; }
[data-theme=light] { color-scheme: light; }
[data-theme=dark] { color-scheme: dark; }
html { scrollbar-gutter: stable; }

:where(a, button, input, select, textarea, [tabindex]):focus-visible {
  outline: 2px solid var(--color-brand-ink);
  outline-offset: 2px;
}
```

- **`--x-*: initial` deletes Tailwind's defaults,** so `rounded-xl` or `font-bold` don't compile unless the profile adds them. Once daisyUI is removed, `--color-*: initial` does the same for `bg-black` or `text-gray-500`. Spacing can't be locked (v4 multiplies `--spacing`), so the grep checks in §9 catch strays.
- **Swapping the palette:** take the hex values from Appendix A (`.agents/shared/ui-palettes.md`), convert them to HSL (or OKLCH), then re-check `on-brand` on `brand`, `on-danger` on `danger`, every `*-ink` on `surface` and on its `*-soft`, `line-strong` on `surface`, and the fills `brand` and `danger` against `surface` and `canvas` (`check_contrast.exs` in the `phoenix-ui` skill checks them all, and reports the gaps between the three text levels, the separation of the backgrounds and the chroma of the dark greys).
- **Runtime values** use inline variables: `style={"--pct: #{@pct}%"}` with `w-(--pct)`.
- **Body:** `<body class="bg-canvas text-ink antialiased">`.

### 3.4 Theme switching
- **Three states: System / Light / Dark.** Phoenix 1.8's generated theme toggle sets or removes `data-theme` and remembers the choice in `localStorage`; `light-dark()` and the `dark:` variant cover all three states. Its inline `<script>` in the root layout runs before first paint (no flash) and gets `nonce={@csp_nonce}`.
- **Theme-aware assets:** logo and icons in `currentColor`; illustrations with transparent backgrounds or a `bg-surface` frame.
- **Compact control in the header:** one icon button that cycles System → Light → Dark, showing the current mode's icon, with `aria-label="Theme: Dark. Change theme"` (updated on each click). A labelled segmented control or radio group is fine in a settings page or menu, not as an extra header row.

### 3.5 daisyUI (kept by default)

Phoenix 1.8 generates daisyUI and a `core_components.ex` built on it. **Keep both:** reuse what the generator gives and build only what it lacks (§0). daisyUI is the implementation, not the design: these directives (Refactoring UI, the scales, states, contrast) decide how things look and behave, and win wherever daisyUI differs.

- **Never remove it on your own.** Only the user decides, and the profile records it. An empty profile means it stays.
- **One palette:** fill its two themes from the scales, so `base-200` and `canvas` are the same colour. The recipe (theme blocks, variable mapping, which classes primitives wrap) is in `.agents/shared/ui-daisyui.md`; read it before touching `app.css` or a primitive.
- **Small gap, small change:** a primitive keeps the generated daisyUI classes where they meet §6 (variants, sizes, states, contrast) and changes a few, or adds token classes, where they don't. Changes go in `core_components.ex` (app code) and the themes, never in `assets/vendor/` or page CSS.
- **Big gap, rebuild:** when a primitive would override most of daisyUI's look (height, padding, focus, states), rebuild it on the tokens (§6) with no daisyUI classes. Overrides on top of daisyUI break when daisyUI changes; a primitive on the tokens doesn't.
- **After a daisyUI upgrade,** check every primitive that still wraps it, in both themes (§9). Badges and alerts use the token pairs, not daisyUI's derived colours.
- **Templates call primitives,** never raw daisyUI classes, so a later swap touches one file.
- **phx.new's rule** "write your own tailwind-based components instead of using daisyUI" (in `AGENTS.md` or `.agents/rules/`) is replaced by this section.
- **When no primitive uses it,** suggest removing it; the user decides. Then delete its two `@plugin` blocks and vendor files and lock the palette with `--color-*: initial`.
