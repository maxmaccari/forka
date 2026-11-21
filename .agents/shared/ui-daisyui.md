# UI Directives: daisyUI (§3.5 in full)

Reference for the UI directives (`.agents/rules/ui.md`); not always-on. Read it before touching `app.css` or a primitive while the app keeps daisyUI (the default). §3.5 in `ui-tokens.md` has the summary.

## 3.5 daisyUI (kept by default)

Phoenix 1.8 generates daisyUI and a `core_components.ex` built on it. Keep both: reuse what the generator gives and build only what it lacks. daisyUI is the implementation, not the design: the directives (Refactoring UI, the scales, states, contrast) decide how things look and behave, and win wherever daisyUI differs. Never remove it on your own; only the user decides, and the profile records it.

**Why keep it.** It is already there, the generated components already work, and every upgrade of `phx.new` assumes it. Its costs are real but small, and each has a fix below:
- **Two naming systems** (`base-200` vs `canvas`): fill its themes from the same scales, so both name one colour.
- **Derived colours that fail contrast:** use the token pairs where daisyUI derives them.
- **No palette lock:** `--color-*: initial` can't stay, so the §9 greps catch stray palette classes instead.

**When to replace it, one primitive at a time.** A small gap from §6 is a small change in `core_components.ex`. When a primitive would override most of daisyUI's look (height, padding, focus, states), rebuild it on the tokens with no daisyUI classes: overrides on top of daisyUI break when daisyUI changes (v4 to v5 renamed classes), and a primitive on the tokens doesn't. After each daisyUI upgrade, check the primitives that still wrap it, in both themes.

**When none is left.** Once no primitive uses a daisyUI class, suggest removing it; the user decides. Removal gives a locked palette and every colour pair one you chose and checked. phx.new's own rule ("write your own tailwind-based components instead of using daisyUI") aims there from the start; these directives replace it with the gradual path above. To remove: delete its two `@plugin` blocks and vendor files and lock the palette with `--color-*: initial`.

**Either way:** templates call primitives, never raw daisyUI classes, and badges and alerts use the token pairs, not daisyUI's derived colours.

**Setup:** keep `@plugin "../vendor/daisyui" { themes: false; }`, delete `--color-*: initial`, and replace the two generated `daisyui-theme` blocks with themes filled from the **same scales**:

| daisyUI variable | Same as |
|---|---|
| `base-100` / `base-200` / `base-300` / `base-content` | `surface` / `canvas` / `sunken` / `ink` |
| `primary` / `primary-content` | `brand` / `on-brand` |
| `secondary` / `secondary-content` | `brand-soft` / `brand-ink` |
| `accent` / `accent-content` | `accent-soft` / `accent-ink` |
| `neutral` / `neutral-content` | grey-800 / grey-50 (light), grey-200 / grey-900 (dark) |
| `info` / `info-content` | `brand-soft` / `brand-ink` (or a blue scale if the palette has one) |
| `success` / `success-content` | success-700 / white (light), success-300 / success-900 (dark) |
| `warning` / `warning-content` | warning-500 / warning-900 (light), warning-300 / warning-900 (dark) |
| `error` / `error-content` | `danger` / `on-danger` |

In dark mode `primary` and `error` take the light fills of §3.2 (`brand-300` with grey-900 text, `danger-200` with grey-900 text), so daisyUI's buttons keep 3:1 against the card like the primitives do.

```css
@plugin "../vendor/daisyui-theme" {
  name: "light";
  default: true;
  prefersdark: false;
  color-scheme: "light";
  --color-base-100: var(--color-white);
  --color-base-200: var(--color-grey-50);
  --color-base-300: var(--color-grey-100);
  --color-base-content: var(--color-grey-900);
  --color-primary: var(--color-brand-600);
  --color-primary-content: var(--color-white);
  --color-secondary: var(--color-brand-50);
  --color-secondary-content: var(--color-brand-600);
  --color-accent: var(--color-accent-100);
  --color-accent-content: var(--color-accent-900);
  --color-neutral: var(--color-grey-800);
  --color-neutral-content: var(--color-grey-50);
  --color-info: var(--color-brand-50);
  --color-info-content: var(--color-brand-600);
  --color-success: var(--color-success-700);
  --color-success-content: var(--color-white);
  --color-warning: var(--color-warning-500);
  --color-warning-content: var(--color-warning-900);
  --color-error: var(--color-danger-600);
  --color-error-content: var(--color-white);
  --radius-selector: 0.25rem; /* = radius-sm */
  --radius-field: 0.5rem;     /* = radius-md */
  --radius-box: 0.75rem;      /* = radius-lg */
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 1;
  --noise: 0;
}

@plugin "../vendor/daisyui-theme" {
  name: "dark";
  default: false;
  prefersdark: true;
  color-scheme: "dark";
  /* the same variables, filled from the Dark columns of the two tables above */
}
```

- **Derived colours** (`badge-soft`, `btn-soft`, `*-outline` on light fills) mix the role colour with transparency and can fail contrast. Use the token pairs (`bg-success-soft text-success-ink`) instead.
- **Primitives wrap daisyUI classes** while the gap from §6 is small, and are rebuilt on the tokens when it isn't: button → `btn` + `btn-primary` / `btn-outline` / `btn-link` / `btn-error`, `btn-sm` / `btn-lg`; card → `card` + `card-body` + `card-title` + `card-actions`; alert → `alert`; modal → `modal` + `modal-box`. Badges keep the token pairs.
