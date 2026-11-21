---
trigger: always_on
description: UI directives §10–§12: surfaces, scoped exceptions and the app profile
---

# UI Directives: surfaces and exceptions

Part of the UI directives; start at `ui.md`. The app's `ui-profile.md` wins over these defaults.

## 10. Surfaces

An app usually has several **surfaces**, and each screen belongs to one. The profile maps the app's screens to them. Exceptions (§11) are enabled per surface, never for the whole app.

| Surface | Typical screens | Exceptions it may enable |
|---|---|---|
| **Reading / content** | Articles, stories, documentation, long forms | None. Defaults only, plus §4.3. |
| **Productivity / utility** | Dashboards, booking, scheduling, settings | EX-01 |
| **Admin / back office** | Data tables, moderation, reports | EX-04 |
| **Catalog / e-commerce** | Image-led browse pages: products, rentals, recipes | EX-05, EX-06, EX-08 |
| **Marketing** | Landing pages, pricing, sign-up | EX-02, EX-07, EX-08 |
| **Moments** | Onboarding, milestones, success screens | EX-02, EX-08 |
| **Social / community** | Feeds, comments, chat, reactions | EX-02, EX-03 |
| **Games / party** | Boards, scoreboards, lobbies, live play | EX-02, EX-03, EX-08 |

---

## 11. Scoped exceptions

An exception replaces a default **only on the surfaces it names, and only with its guardrails**. To use one, enable it in the profile for specific screens, and name it in the component's `@doc` and in the PR description ("EX-04 on Admin tables"). A pattern used outside its surfaces is a bug.

**EX-01 · A bright single-hue accent (cyan, sky, blue)** (default: the profile palette's brand scale)
- **Allowed on:** Productivity / utility, when the profile picks a cool palette (for example palettes 1, 2, 8 or 9).
- **Guardrails:** it is the app's only brand colour. `brand` moves to 700 so white text passes 4.5:1, and `brand-ink` to 700 on white.

**EX-02 · Gradient banner** (default: a solid `hero` banner)
- **Allowed on:** Moments, Marketing, Social / community, Games / party.
- **Guardrails:** two hues no more than about 30° apart, both from the palette (`from-brand-900 to-brand-700`); text passes 4.5:1 against **both** ends; one banner per screen, never the only place the information appears; respect `prefers-reduced-motion` if it animates.

**EX-03 · Emoji** (default: inline SVG icons)
- **Allowed on:** Social / community and Games / party, for user-written content, reactions and celebration copy.
- **Guardrails:** never the only signal (pair with text, or an `aria-label` on its button); decorative emoji in system copy go in `<span aria-hidden="true">`; never in headings, buttons, status badges or navigation.

**EX-04 · Outlined badges** (default: filled soft tints)
- **Allowed on:** Admin / back office tables, for status columns.
- **Guardrails:** `variant="outline"` on the same `badge` component (`bg-transparent ring-1 ring-inset ring-current` with the tone's `*-ink` text), so labels stay identical across the app; re-check contrast if the table sits on `sunken`; the label is the status in words.

**EX-05 · Two-column cards on phones** (default: one column)
- **Allowed on:** Catalog / e-commerce, when the card leads with an image.
- **Guardrails:** each card shows the image, a title of one or two lines (`line-clamp-2`), one meta fact (a price) and at most one badge; cards at least 160px wide, one column below 360px; descriptions move to the detail page.

**EX-06 · The whole card as one link** (default: `<.card>`, an article with its own action)
- **Allowed on:** Catalog / e-commerce, when opening the item is the card's only action. Use `<.link_card>`.
- **Guardrails:** no buttons or links inside; the link's accessible name is the title (`aria-labelledby` if the card holds more text); a visible focus ring around the whole card; the hover zoom respects reduced motion.

**EX-07 · Large light display headings** (default: hierarchy from weight)
- **Allowed on:** Marketing, one hero heading per page.
- **Guardrails:** at least `text-5xl`; the profile adds `--font-weight-light: 300`; a few words only, everything else stays at 400 or heavier; 4.5:1 contrast, never thin type over an image without a solid backing.

**EX-08 · Tilted sticker tags** (default: none)
- **Allowed on:** Catalog / e-commerce (prices, "Sale"), Marketing, Moments, Games / party ("Winner!").
- **Guardrails:** one or two words, at least `text-sm font-semibold`; `-rotate-1` or `-rotate-2` at most, no skew on longer text; at most two per screen; on a solid token pair (`bg-accent-soft text-accent-ink` or `bg-brand text-on-brand`), or a highlighter pair the profile defines (for example `accent-200` behind `ink`) and measures at 4.5:1 in both themes.

**EX-09 · Opacity for muted text** (default: `ink-muted` / `ink-subtle`)
- **Allowed on:** single-surface UIs only, where text never sits on anything but `canvas` (a full-screen game board, a kiosk).
- **Guardrails:** check 4.5:1 for the resulting colour on that background in both themes. If a second background appears, switch back to the tokens.

**Adding an exception:** name the default it replaces and why it fails there, the surfaces where it's allowed, and its guardrails with contrast numbers in both themes. Add it here with the next `EX-` id before any app ships it.

---

## 12. App profile (`ui-profile.md`)

Each app keeps a short profile next to these files. It records only what differs from the defaults:

1. **Palette:** which palette (Appendix A) fills each scale; light and dark may use different ones.
2. **daisyUI:** kept (the default) or removed by the user (§3.5).
3. **Fonts and weights:** the families, how they're self-hosted, and any weights beyond 400 / 600.
4. **Radii:** `radius-sm`, `-md`, `-lg` if they differ.
5. **Scale values:** the HSL `@theme` block for the app's scales.
6. **Token overrides:** every semantic token that differs from §3.2, with the reason (usually contrast), and the lowest contrast pairs you measured.
7. **Personality and component variants:** the signature motif, and the chosen variant for buttons, inputs, badges, tabs, alerts and cards.
8. **Surfaces and archetypes:** which of the app's screens are which surface (§10) and which layout archetype (§1: Page, Form, Reading, Workspace).
9. **Enabled exceptions:** which `EX-` ids apply, on which screens.
10. **Domain notes:** the states, confirmations, CTAs and labels that matter most in that domain.
