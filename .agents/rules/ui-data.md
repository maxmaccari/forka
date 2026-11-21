---
trigger: always_on
description: UI directives §13: Workspace screens. Data grids, ledgers and planners: layout, dense tables, inline values, status pills, the primary metric, the inspector, dark mode on dense screens and the visual review
---

# UI Directives: Workspace screens

Part of the UI directives; start at `ui.md`. The app's `ui-profile.md` wins over these defaults. This file applies to the **Workspace** archetype (§1): budgets, ledgers, registers, planners, boards, admin tables, anything where the screen is a grid of values the user works in for minutes at a time. It takes the spreadsheet's density and keyboard flow and keeps the rest of the system.

## 13. Workspace screens

### 13.1 Layout
- **Full width, full height.** `main` is `flex-1 min-w-0 overflow-y-auto`; the page itself doesn't scroll. No `max-w-*` on the grid: spare width widens the name column and the inspector, never a margin.
- **Three columns:** sidebar `w-64` (navigation and the app's "accounts", "projects" or equivalent list with their totals), the grid, and an inspector `w-80` (§13.6). Below `lg` the inspector becomes a drawer opened from the selected row; below `md` the sidebar becomes the menu (§2.2).
- **Toolbar above the grid, one row:** period picker or scope at the left, next to what it controls; view chips in the middle; display toggles and undo/redo at the right. It wraps into a menu, never into a second row (§2.2).
- **Sticky where the eye returns:** the column header and the primary metric stay fixed while the grid scrolls.
- **Sidebar rows don't wrap:** `truncate` the name, keep the value at the right end of the same line, `tabular-nums`. Negative or problem totals in a `danger` pill; everything else `text-ink-muted`.

### 13.2 Dense tables
- **Row height 40–44px** (`py-2`), one item per row. Secondary facts stay out unless they change the decision; the inspector holds the rest.
- **Numbers:** the UI font with `tabular-nums`, right-aligned, `whitespace-nowrap`, the currency or unit present (§4.13). **Mono is for code and IDs,** not money: it widens columns and reads as a terminal.
- **Column header:** `sticky top-0 bg-surface text-sm font-semibold text-ink-muted`, sentence case, right-aligned over numbers.
- **Group rows:** `font-semibold` with the group's totals and a caret (`aria-expanded`). Their background is at most one step from the rows (`bg-canvas` inside a `bg-surface` table), never a saturated band. Groups organise; they don't compete.
- **Separators:** one 1px `border-line` between rows **or** spacing, never zebra plus borders plus bands.
- **Selection:** the selected row gets `bg-brand-soft` and a 2px `border-l-brand`, `aria-selected="true"`; the inspector shows it. Shift with arrows or click extends the selection (§14.4, §14.11).
- **Totals** live in the group row or a sticky footer, never as loose text under the table.
- **Clickable values** show it: `hover:underline decoration-line underline-offset-4` or an icon on hover (§14.6).

### 13.3 Inline value input
An editable value in a grid **looks like text until hover or focus**. Fifty full input boxes turn a grid into a form and bury the values that matter.

```heex
<input type="text" inputmode="text" enterkeyhint="done" value={@value}
  aria-label={"#{@column} for #{@row_name}"} phx-blur="save" phx-keydown="key" phx-value-id={@id}
  class="w-28 rounded-sm bg-transparent px-2 py-1 text-right tabular-nums text-ink
         ring-1 ring-inset ring-transparent hover:ring-line focus:bg-surface focus:ring-2 focus:ring-brand focus:outline-none" />
```
- Saves on blur and Enter, cancels on Esc, and the dependent totals update at once (§14.8). Tab moves to the next row's value.
- Accepts the formats and arithmetic of §14.1; after the save the field shows the normalised value.
- `inputmode="text"` rather than `decimal`, so the phone keyboard has `+` and `-`.
- The `<.input>` primitive with its full box stays for Form screens.

### 13.4 Value pill
The one column that carries status (available, balance, remaining) renders through a `value_pill`:
```elixir
attr :tone, :string, default: "neutral", values: ~w(neutral success warning danger brand)
attr :icon, :string, default: nil, doc: "a -micro icon that repeats the tone's meaning"
# neutral: no fill, text-ink-subtle; others: rounded-full px-2 py-0.5 tabular-nums font-semibold
#   with the tone's bg-*-soft text-*-ink
```
- **Zero or resolved is neutral:** plain text, no pill. Colour appears only on rows that need attention (§2.4 "Colour is a budget").
- **Never colour alone:** the pill carries an icon (`hero-exclamation-circle-micro`, `hero-clock-micro`, `hero-check-circle-micro`) or an `sr-only` word for the state.
- The same `tone` vocabulary as `badge` (§6): success = fine, warning = pending or underfunded, danger = overspent or negative, brand = projected.

### 13.5 Primary metric
Each Workspace has one number the whole screen serves (money left to assign, items awaiting approval, the day's total). It renders once, at the top, through a `primary_metric` component with a `tone`, a **sentence that explains the state** and **the action that resolves it**, in the same piece:
- `success`: "$1,200.00 to assign · [Assign]"
- `neutral`: "All money assigned" (the ideal state is quiet, no fill)
- `danger`: "$300.00 more assigned than you have · [Fix it]"

It never sits in a neutral `sunken` box when something needs doing, and it never competes with a second metric of the same size.

### 13.6 Inspector
A fixed `aside` at the right (`w-80 shrink-0 border-l border-line bg-surface overflow-y-auto`), with three designed states:
- **Nothing selected:** the screen's summary (totals, the period's figures, the one-click helpers). Never empty.
- **One item:** its detail, the maths behind its values (§14.7), its target or settings, and the actions on it. The inspector is where secondary facts and the full input boxes go.
- **Several items:** the sum and the bulk actions that are valid for the selection (§14.11).

Below `lg` it is a drawer opened from the row and closed with Esc or a Close button. It touches the viewport edge; it is not a card floating in the content column.

### 13.7 Progress and targets
- A progress bar appears **only when it informs**: a target not yet met, a period partly elapsed. A met target is a `hero-check-circle-micro` beside the name, not a full bar plus a repeated "complete" label on every row.
- Colour by **state** (`success`, `warning`, `danger`, `sunken` for empty), not by brand. Segments when the period has parts (weeks of a month).
- `role="progressbar"` with `aria-valuenow`, `aria-valuemin`, `aria-valuemax` and an `aria-valuetext` that says it in words ("$50.00 of $200.00 by the 15th"). Height `h-1` to `h-2`.

### 13.8 Dark mode on dense screens
Dense screens expose every dark-mode weakness at once: dozens of inputs, three backgrounds and a brand fill in the same view. Beyond §2.4 and §2.5:
- **Brand fill at 3:1 or more** against `surface` and `canvas`: in dark, `brand` maps to a light step with `on-brand` = grey-900 (§3.2). A saturated `brand-500` or `-600` on `grey-800` measures about 2:1 and the primary button disappears.
- **Disabled is its own state:** `bg-sunken text-ink-subtle cursor-not-allowed`, no brand colour, and the reason in text next to it, linked with `aria-describedby` ("No pending items to approve"). Never `opacity` alone: in dark it looks like the enabled button.
- **Inputs read as inputs:** on `canvas`, where `sunken` may equal it in dark, the field keeps `ring-1 ring-line-strong`; inline value inputs rely on their hover and focus rings.
- **Native widgets wear the theme:** `color-scheme` is set (§3.3) so date pickers and scrollbars follow it; `<input type="file">` is `sr-only` behind the app's own button and drop zone, which show the chosen file's name in the app's language. The browser's "Choose file" label follows the browser's locale, not `lang`.

### 13.9 Visual review
The §9 greps and `check_contrast.exs` catch tokens; they don't see the whole screen. Before calling a Workspace (or any screen) done:
1. **Screenshots** at 1440px and 375px, light and dark (the `phoenix-ui` skill's `scripts/screenshot.sh`).
2. **Squint test:** in three seconds, which element is primary? If two compete, soften one (§0.3).
3. **Count:** status colours on screen (more than about a fifth of rows → §13.4), identical bordered boxes (more than about ten → §13.3), backgrounds (more than three → §2.5).
4. **Width:** dead space wider than the sidebar → wrong archetype (§1).
5. **Dark:** does the primary button still read as a button, do the three text levels still differ, can you tell disabled from enabled?
