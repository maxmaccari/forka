---
trigger: always_on
description: Forka's UI choices. Overrides the defaults in the UI directives (ui.md and the ui-*.md files it lists)
---

# Forka UI profile

Applies the UI directives (`ui.md` and the files it lists). Anything not listed here follows them.
Design canvas: https://claude.ai/artifact/3uu2uFcEyufwSknxD3scgj (status: draft, 2026-10-31, waiting on Maxsuel's answers).

## 0. Stack note
Forka is on Phoenix 1.7, LiveView 1.0 and Tailwind v3 (with daisyUI because Backpex needs it). The directives target Phoenix 1.8, LiveView 1.1 and Tailwind v4. Upgrade first (own task), then build the player UI on the `app.css` template (§3.3) with the scales below.

## 1. Palette
- **Palette 19** (Appendix A): Indigo + Orange (Vivid), Cool Grey; supporting Yellow (Vivid), Red (Vivid), Green (Vivid). Borrowed: Cyan (Vivid) 400 and Magenta (Vivid) 400 as player colours only.
- `brand` = Orange (Vivid), `night` (extra scale) = Indigo, `grey` = Cool Grey, `accent` / `warning` = Yellow (Vivid), `success` = Green (Vivid), `danger` = Red (Vivid).
- **Light mode:** indigo-tinted canvas, white surfaces, indigo ink. **Dark mode:** an indigo "night stage" (night-900 canvas, night-800 surfaces). The same orange buttons in both.

## 2. daisyUI
Kept only for the Backpex back office (`/admin`), which depends on it. Player screens never use daisyUI classes or components; they use the semantic tokens below. Because daisyUI stays, don't add `--color-*: initial`.

## 3. Personality
- **Tone:** playful party game, chunky and tactile, friendly copy in pt-BR ("Bora jogar!", "Sua vez, Lia!"). No gallows and no stick figure.
- **Signature motif: the rope that wears out** (`<.rope tries={n} size={:lg | :md | :sm}>`). A real twisted rope (SVG): each miss frays fibres and thins its middle; on the sixth miss it snaps into two jagged ends ("Corda rompida") and the player is out. Completing a word gives a new rope ("Cura", back to 6). Sizes: `lg` 240×48 for moments, `md` 132×26 for your own rope and desktop player cards, `sm` 52×13 plus "3/6" for opponent chips on phones. Always `role="img"` with an `aria-label` ("Corda: 4 de 6 tentativas") and visible text. A shake on a miss and the snap are disabled under `prefers-reduced-motion`. Colours: `--color-rope` accent-300, `--color-rope-twist` accent-500, `--color-rope-edge` brand-800 (brand-900 dark).
- **Fonts (decided 2026-10-31):** `--font-display` = Fredoka (headings, word tiles, keys, scores); `--font-sans` = Nunito (all other UI). No other fonts. All OFL, Latin Extended, variable; self-host in `priv/static/fonts`. Display font on headings, word tiles, keys, buttons and scores only.
- **Extra weights:** `--font-weight-bold: 700` (display headings, tiles) and `--font-weight-extrabold: 800` (small UI labels in Nunito: eyebrows, badges).
- **Radii (large = playful):** `--radius-sm: 0.625rem` (tiles, keys), `--radius-md: 1rem` (buttons, inputs), `--radius-lg: 1.25rem` (cards, chips), `--radius-xl: 1.5rem` (sheets). Avatars and pills are `rounded-full`.
- **Depth:** game pieces (primary button, tiles, keys, slots) get a solid bottom "lip" instead of a soft shadow: `shadow-[0_4px_0_var(--color-brand-700)]` style, declared as tokens `--shadow-lip-brand`, `--shadow-lip-tile`, `--shadow-lip-accent`. Pressing drops the lip and moves the piece down 4px. Cards keep `shadow-2`; dark mode drops soft shadows.
- **Component variants:** buttons solid brand with lip (primary), outline with a 2px `line-strong` ring (secondary), link (tertiary); inputs filled `sunken`; badges soft pills; chips as toggle pills (`aria-pressed`); alerts and moments as bottom sheets on `hero`; cards `surface` + `rounded-lg`.

## 4. Scales and token overrides

```css
@theme {
  --font-sans: "Nunito", ui-sans-serif, system-ui, sans-serif;
  --font-display: "Fredoka", "Nunito", ui-sans-serif, sans-serif;
  --font-weight-bold: 700;
  --font-weight-extrabold: 800;

  --color-grey-50: hsl(216 33% 97%);  --color-grey-100: hsl(214 15% 91%);
  --color-grey-200: hsl(210 16% 82%); --color-grey-300: hsl(211 13% 65%);
  --color-grey-400: hsl(211 10% 53%); --color-grey-500: hsl(211 12% 43%);
  --color-grey-600: hsl(209 14% 37%); --color-grey-700: hsl(209 18% 30%);
  --color-grey-800: hsl(209 20% 25%); --color-grey-900: hsl(210 24% 16%);

  --color-brand-50: hsl(24 100% 93%);  --color-brand-100: hsl(22 100% 85%);
  --color-brand-200: hsl(20 100% 77%); --color-brand-300: hsl(18 100% 70%);
  --color-brand-400: hsl(16 94% 61%);  --color-brand-500: hsl(14 89% 55%);
  --color-brand-600: hsl(12 86% 47%);  --color-brand-700: hsl(10 93% 40%);
  --color-brand-800: hsl(8 92% 35%);   --color-brand-900: hsl(6 96% 26%);

  --color-night-50: hsl(221 68% 93%);  --color-night-100: hsl(221 78% 86%);
  --color-night-200: hsl(224 67% 76%); --color-night-300: hsl(225 57% 67%);
  --color-night-400: hsl(227 50% 59%); --color-night-500: hsl(227 42% 51%);
  --color-night-600: hsl(228 45% 45%); --color-night-700: hsl(230 49% 41%);
  --color-night-800: hsl(232 51% 36%); --color-night-900: hsl(234 62% 26%);
  --color-night-950: hsl(234 90% 25%); /* Indigo (Vivid) 900 #061178: dark-mode stage */

  --color-accent-50: hsl(49 100% 96%);  --color-accent-100: hsl(48 100% 88%);
  --color-accent-200: hsl(48 95% 76%);  --color-accent-300: hsl(48 94% 68%);
  --color-accent-400: hsl(44 92% 63%);  --color-accent-500: hsl(42 87% 55%);
  --color-accent-600: hsl(36 77% 49%);  --color-accent-700: hsl(29 80% 44%);
  --color-accent-800: hsl(22 82% 39%);  --color-accent-900: hsl(15 86% 30%);

  --color-success-50: hsl(125 65% 93%);  --color-success-100: hsl(127 65% 85%);
  --color-success-200: hsl(124 63% 74%); --color-success-300: hsl(123 53% 55%);
  --color-success-400: hsl(123 57% 45%); --color-success-500: hsl(122 73% 35%);
  --color-success-600: hsl(122 80% 29%); --color-success-700: hsl(125 79% 26%);
  --color-success-800: hsl(125 86% 20%); --color-success-900: hsl(125 97% 14%);

  --color-danger-50: hsl(0 100% 95%);   --color-danger-100: hsl(0 100% 87%);
  --color-danger-200: hsl(0 100% 80%);  --color-danger-300: hsl(0 91% 69%);
  --color-danger-400: hsl(0 83% 62%);   --color-danger-500: hsl(356 75% 53%);
  --color-danger-600: hsl(354 85% 44%); --color-danger-700: hsl(352 90% 35%);
  --color-danger-800: hsl(350 94% 28%); --color-danger-900: hsl(348 94% 20%);

  /* Player colours (categories, fixed in both themes; always with the initial) */
  --color-player-1: var(--color-brand-400);
  --color-player-2: hsl(178 78% 57%);  /* Cyan (Vivid) 400 #3AE7E1 */
  --color-player-3: hsl(300 82% 60%);  /* Magenta (Vivid) 400 #ED47ED */
  --color-player-4: var(--color-accent-300);
  --color-player-5: var(--color-success-300);
  --color-player-6: var(--color-night-200);
  --color-on-player: var(--color-night-900);

  /* Semantic overrides (everything else as §3.2) */
  --color-canvas: light-dark(var(--color-night-50), var(--color-night-900));
  --color-surface: light-dark(var(--color-white), var(--color-night-800));
  --color-sunken: light-dark(var(--color-grey-50), var(--color-night-900));
  --color-line: light-dark(var(--color-night-100), var(--color-night-700));
  --color-line-strong: light-dark(var(--color-night-500), var(--color-night-300));
  --color-ink: light-dark(var(--color-night-900), var(--color-night-50));
  --color-ink-muted: light-dark(var(--color-night-700), var(--color-night-100));
  --color-ink-subtle: light-dark(var(--color-night-600), var(--color-night-200));
  --color-brand: var(--color-brand-400);
  --color-on-brand: var(--color-night-900);
  --color-brand-strong: var(--color-brand-300);
  --color-brand-ink: light-dark(var(--color-brand-700), var(--color-brand-300));
  --color-hero: light-dark(var(--color-night-900), var(--color-night-950));
  --color-hero-ink: var(--color-night-50);
  --color-hero-muted: var(--color-night-200);
  --color-rope: var(--color-accent-300);
}
```

- **Why each override:** `brand` is Orange (Vivid) 400 with dark `on-brand` text, because white on orange only passes at 700 (too dull for a game button); `brand-ink` 700 / 300 for links and focus; ink and lines come from Indigo so the night stage and light canvas share one temperature; `hero-muted` added for secondary text on the stage.
- **Lowest contrast pairs measured (WCAG 2.x):** `on-player` on player-3 magenta 4.56:1 (both themes); `brand-ink` on canvas, light 4.66:1; `brand-ink` on surface, dark 4.62:1; `ink-subtle` on surface, dark 4.58:1; `on-brand` on `brand` 5.03:1; `line-strong` on canvas 4.53:1 light, 4.77:1 dark (3:1 target); completed tile text success-900 on success-300 5.15:1.

## 5. Surfaces

| Screen | Surface |
|---|---|
| Room list, room (`/salas/:id`, joined by link) | Games / party |
| Turn-order draw, gameplay, word complete + heal, elimination, results | Games / party |
| Sign-up, log in, settings | Productivity / utility |
| `/admin` (Backpex) | Admin / back office |

## 6. Enabled exceptions
- **EX-02 (gradient banner):** the word-complete "Cura" moment only (night-900 to night-800).
- **EX-08 (tilted sticker):** "+100 pts" on the word-complete moment and "Vencedora!" / "Vencedor!" on results; at most one per screen.
- **EX-03 (emoji):** allowed for future chat or reactions only; never in the board, keys, scores or buttons.
- **Not enabled:** EX-09 (the board has several backgrounds), EX-07.

## 7. Domain notes
- **Components:** `ForkaWeb.GameComponents`: `cord`, `player_chip`, `word_tiles`, `letter_key`, `keyboard`, `turn_banner`, `moment_sheet`, `podium`.
- **Keyboard:** alphabetical A–Z grid, 7 columns on phones (keys at least 44×48px), 13 columns on desktop; physical-keyboard input on desktop. Accents and Ç are folded (guessing A reveals Ã, C reveals Ç), so there are no accent keys. Key states: free, right (success tint plus ring), wrong (struck through on `sunken`); used keys are `disabled` with an `aria-label` like "E, certa".
- **Word tiles:** spaces split words into groups that wrap; hyphens are pre-revealed. An sr-only line reads the word ("O, oculta, …").
- **Turn:** the current player's chip has a 3px `brand` ring and a "Vez" tag (`aria-current`); the turn heading is `aria-live="polite"`. Other players' turns disable the keyboard with "Aguarde: vez de Bruno".
- **Scoring copy:** 10 points per revealed letter; completing a word adds 10 per letter as a bonus and heals to a new rope (6 tries); the closer starts the next word. Eliminated players keep their score with a lock icon ("pontos travados").
- **Moments:** word complete, elimination and end of game are bottom sheets on `hero` with one primary action; animations (`pop`, rope shaking, rope snapping, podium rising) are disabled under `prefers-reduced-motion`.
- **Confirmations:** "Desistir da partida" lives in the in-game menu and asks for confirmation with solid `danger` only in the dialog.

## 8. Phases (design canvas, 2026-10-31)
- **Phase 1, what the code does today:** 2 to 6 players, the owner sets name, max players, language and categories, starts and can pass ownership; an account is required; 2 words per player; the order is drawn once at the start; a hit gives +10 per letter and keeps the turn, a miss costs 1 of 6 tries and passes the turn; the closer gets 10 per letter, a new rope and starts the next word; with no tries left the player is out until the end with points locked; the game ends when all words close or everyone is out ("Todo mundo caiu!"); give up in-game, leave only before the start; the owner restarts; rooms are shared by link (no short code); live room list.
- **Phase 2, needs code changes:** out for the current word only ("Fora desta palavra"); 30 s turn timer, running out costs the turn and 1 try; disconnected badge, turn skipped after a countdown; order rotates each word; short room code; guest join by name.
- **Phase 3:** admin CSV import (category,language,name,hint) with preview and result; hints as clues, emphasised card and a no-hint state; sounds (off by default), vibration, animations switch, win confetti.
