---
trigger: always_on
description: UI directives §14: interaction. Forgiving input with arithmetic in number fields, smart defaults, undo over confirm, keyboard, comboboxes, actions on the data, live consequences, review queues, guided rituals, bulk actions
---

# UI Directives: interaction

Part of the UI directives; start at `ui.md`. The app's `ui-profile.md` wins over these defaults. §2–§13 say how a screen looks; this file says how it behaves. The principle behind all of it: **the app adapts to how the person already thinks, and makes every step cheap to take back.**

## 14. Interaction

### 14.1 Forgiving input
A field accepts what people type and normalises it; it never makes them reformat.
- **Numbers and money:** the app's locale formats (`1,234.56` or `1.234,56`), the currency symbol (`$50`, `€ 50`), `-` or `−` for negatives, blank = 0, and **arithmetic** (`100 + 50` → `150`; `+ - × ÷`, `x` and `*` for times, parentheses). Division rounds to the cent only at the end.
- **Dates:** the locale's short form (`9/11`, `09/11/2026`), words (`hoje`, `today`), and in the picker `T` = today, `+`/`-` = a day, `M`/`Shift+M` = first/last of the month.
- **Normalise on blur or Enter, then show the result** in the field; while typing, the field is never rewritten. An expression shows a live preview beside it (`= $150.00`, `text-ink-subtle`), and the result is announced in an `aria-live="polite"` region ("100 + 50 = $150.00").
- **Invalid input stays in the field** with an error that says what is accepted ("Use numbers and + − × ÷"), never a silent reset to zero.
- **One parser per value type, on the server,** shared by every field of that type (`Format.parse_cents/1`, `Calc.eval/2`). Never `Code.eval_string`, never `eval` in JavaScript.
- **Say that it's accepted:** a placeholder or helper ("Accepts sums: 100 + 50") on the first field of a form, the shortcut in the picker's tooltip. A hidden power nobody discovers is a feature that doesn't exist.

**Recipe: arithmetic in number fields** (`lib/<app>_web/calc.ex`). Each number token, currency prefix included, goes to the app's own parser, so locale and currency come from one place and `Calc` knows neither. A blank field evaluates to the parser's zero.
```elixir
defmodule ForkaWeb.Calc do
  @moduledoc "Evaluates + − × ÷ and parentheses typed in number fields. No Code.eval_string."
  @ops %{"+" => :add, "-" => :sub, "−" => :sub, "*" => :mult, "x" => :mult, "×" => :mult,
         "/" => :div, "÷" => :div, "(" => :open, ")" => :close}
  # A number may carry a currency prefix ("$50", "R$ 1.234,56", "€ 50"): anything that is
  # not a digit, space or operator, then the digits. The prefix goes to parse_number as typed.
  @number ~r/\A[^\d\s+\-−*x×\/÷()]*\s?\d[\d.,]*/u
  @op ~r/\A[-+−*x×\/÷()]/u

  @spec eval(String.t(), (String.t() -> {:ok, Decimal.t()} | :error)) :: {:ok, Decimal.t()} | :error
  def eval(text, parse_number) do
    case String.trim(text) do
      "" ->
        parse_number.("0")

      text ->
        with {:ok, tokens} <- tokenize(text, []),
             {:ok, value, []} <- expr(tokens, parse_number),
             do: {:ok, value},
             else: (_ -> :error)
    end
  end

  @doc "True when the text holds an operator after its first character, so the field shows a preview."
  def expression?(text), do: String.match?(String.trim(text), ~r/.[-+−*x×\/÷]/u)

  defp tokenize("", acc), do: {:ok, Enum.reverse(acc)}
  defp tokenize(" " <> rest, acc), do: tokenize(rest, acc)

  defp tokenize(text, acc) do
    case Regex.run(@number, text) || Regex.run(@op, text) do
      [m] -> tokenize(binary_part(text, byte_size(m), byte_size(text) - byte_size(m)), [Map.get(@ops, m, {:num, m}) | acc])
      nil -> :error
    end
  end

  # expr := term (("+" | "-") term)*   term := factor (("*" | "/") factor)*   factor := "-" factor | "(" expr ")" | number
  defp expr(tokens, p), do: with({:ok, v, rest} <- term(tokens, p), do: expr_rest(v, rest, p))
  defp expr_rest(l, [op | rest], p) when op in [:add, :sub],
    do: with({:ok, r, rest} <- term(rest, p), do: expr_rest(apply(Decimal, op, [l, r]), rest, p))
  defp expr_rest(l, rest, _p), do: {:ok, l, rest}

  defp term(tokens, p), do: with({:ok, v, rest} <- factor(tokens, p), do: term_rest(v, rest, p))
  defp term_rest(l, [op | rest], p) when op in [:mult, :div] do
    with {:ok, r, rest} <- factor(rest, p), false <- op == :div and Decimal.equal?(r, Decimal.new(0)),
         do: term_rest(apply(Decimal, op, [l, r]), rest, p),
         else: (_ -> :error)
  end
  defp term_rest(l, rest, _p), do: {:ok, l, rest}

  defp factor([:sub | rest], p), do: with({:ok, v, rest} <- factor(rest, p), do: {:ok, Decimal.negate(v), rest})
  defp factor([:open | rest], p) do
    case expr(rest, p) do
      {:ok, v, [:close | rest]} -> {:ok, v, rest}
      _ -> :error
    end
  end
  defp factor([{:num, s} | rest], p), do: with({:ok, v} <- p.(s), do: {:ok, v, rest})
  defp factor(_tokens, _p), do: :error
end
```
`parse_cents/1` calls `Calc.eval(text, &parse_decimal/1)` and rounds to cents at the end, so every money field in the app gains arithmetic in one place. Tests: `"100+50"`, `"1,234.56 + 0.44"`, `"$50 + 10"`, `"-50"`, `"2 x (10 + 5)"`, `"10/3"` (rounds), `""` (zero), `"10/0"`, `"1+"` and `"abc"` (errors).

### 14.2 Smart defaults
The best field is the one that already holds the right value. Before adding a field, ask what the most likely value is and prefill it **from the user's own history**, never from a generic guess: the last category used with this payee, today's date, the account or project on screen, the amount that fixes the problem shown. Prefilled values stay editable and look like any other value.

### 14.3 Undo over confirm
The cost of the protection follows the cost of the mistake (extends §4.2).
- **Reversible and frequent → act, then offer Undo:** a toast with the action in words and an Undo button, 6–8 seconds, `role="status"` so it's announced; `Cmd/Ctrl+Z` where the screen has a focused grid. Undo is a server action (the toast's button sends `undo` with the change's id), not browser state, so it survives a refresh within its window.
- **Irreversible → confirm** in a modal that names the object and the consequence (§4.2), or a guided flow (§14.10).
- **Automatic steps are always undoable** (§14.9).

### 14.4 Keyboard
Someone who uses the screen every day finishes the task without the mouse.
- **Grids:** `↑`/`↓` move between rows, `Enter` edits or saves, `Esc` cancels, `Tab` follows reading order into the next field, `Shift+↑/↓` extends the selection, `Cmd/Ctrl+↑/↓` collapses or expands groups.
- **Mnemonic single-key shortcuts** (`A` approve, `N` new) act only when no input has focus and can be turned off in settings (WCAG 2.1.4). `?` opens the shortcut list; buttons show their key in the tooltip.
- **Focus is always visible** (§3.3 outline) and moves with the action: after a row is deleted, to the next row; after a modal closes, back to its trigger.

### 14.5 Pick by typing
More than about seven options is a search, not a menu: a combobox (`role="combobox"` + listbox) that filters as you type, groups options, and lets you create a new one inline when the domain allows ("Create payee *Padaria*"). `<select>` stays for short, fixed lists (month, status). Disabled options are visible and say why.

### 14.6 The action lives on the data
The shortest path to fix a number is to click it. A value that can be acted on is a button or link styled as a value with a hover affordance (§13.2), and opens an **anchored popover** (the `popover` attribute with CSS anchor positioning, or `<.portal>` with a hook) holding only that action: "Move $[50.00] to [category ▾] · OK". No generic "Actions" menu, no detour through another page.

### 14.7 Show the maths
Every computed number explains itself: the formula inline when it's short ("Cleared + Uncleared = Working balance", `+` and `=` in `text-ink-subtle`), or one click away in the inspector ("Carried over $20 + Assigned $100 − Spent $70 = Available $50"). A target is a sentence ("$50.00 more by the 15th"), not a bare percentage.

### 14.8 Live consequences
A single value saves on blur or Enter, with no Save button, and the totals that depend on it change at once; the saving state shows on the value (`phx-change-loading:opacity-60`). A form with several fields keeps Save and validation (§7). Don't mix the two in one screen.

### 14.9 Automation proposes, the person approves
Imports, rules, matches and suggestions land as a **visible draft or review queue**: a count in the view chip ("To approve · 12"), rows marked pending, approve one or all (§14.11), reject with Undo. What the automation did is written where the row is ("Matched with the entry from 3 Nov", "Category from the rule *Pharmacy*"), and any automatic step can be unmatched or reverted.

### 14.10 Rituals are guided, and the common case is one click
A recurring procedure (reconcile, close the month, send the batch) opens with its most likely outcome as a question: "Is your bank balance $4,930.00? [Yes, it matches] [No, let me fix it]". Yes finishes. No leads through the steps, each showing the difference so far and ending in a named action ("Create adjustment and finish"). Guided flows remember where the person left off.

### 14.11 Bulk actions appear with the selection
A multi-selection (§13.2) swaps the toolbar's or inspector's single-item actions for bulk ones, showing **only the actions valid for the whole selection** ("Categorise 4", "Approve 4"), with the count in the label. Nothing bulk is visible with one or zero items selected.

### 14.12 Views are to-do lists
Filters that match a state (underfunded, overdue, needs approval) are chips above the grid; chips for states that don't occur are hidden, so a visible chip is also an alert. View definitions are shared data; which view is open is URL or device state (§7), and the count in the chip is a live assign.
