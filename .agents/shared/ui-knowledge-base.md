# UI knowledge base (digest)

A text digest of the design knowledge base, written so agents can apply it **without the source PDFs**. Every number, hex value and font name here is copied from the sources. The PDFs stay useful as visual reference (screenshots and wireframes), but they are optional.

| Source | Version | Covered here |
|---|---|---|
| Refactoring UI (book) | v1.0.2 | Sections 1–8: every chapter as directives, plus the exact spacing, type and shadow scales |
| Color Palettes | v1.1.0 | Section 10: all 24 palettes and all 31 colour scales, 10 hex shades each |
| Font Recommendations | v1.0.1 | Section 9: all 32 recommendations (headlines, articles, application UI) with sizes, weights and licences |
| Component Gallery | v1.1.0 | Section 11: every component and its named variants |
| Videos: *Designing Content*, *Designing a Complex Form*, *Designing a Dashboard* | — | **Not covered.** They are walkthroughs that apply the same principles; keep them as optional viewing |

**How the files fit together**
- This file holds the **design knowledge** (what good looks like, exact values).
- The UI directives (`.agents/rules/ui.md` and the `ui-*.md` files it lists) hold **behaviour and components** (semantic tokens, states, HEEx recipes, accessibility, scoped exceptions). They apply this file and don't repeat it.
- `.agents/rules/ui-profile.md` holds **this app's choices** (which palette, which fonts, final token values).
- Precedence: current best practice first, as the UI directives record it (`ui.md`, "Precedence"); where they say a newer practice has moved past this knowledge base (fluid display type, OKLCH, font picks), the directives win. Otherwise this knowledge base settles design principles, then the directives, then the app profile's choices within them. The profile overrides the directives' defaults, never the design principles.

---

## 1. Process

1. **Start with a feature, not the layout.** Design one real piece of functionality (for example "search for a flight") before the shell, nav or logo.
2. **Detail comes later.** Explore in low fidelity; decide typeface, shadows and icons once the layout works.
3. **Design in greyscale first.** Make spacing, contrast and size do the work; add colour afterwards.
4. **Don't over-design.** Work in short cycles: design the simple version, build it, iterate on the working version.
5. **Be a pessimist.** Don't show functionality you aren't ready to build. Ship the smallest useful version; nice-to-haves come later.
6. **Choose a personality,** from four concrete levers:
   - **Font:** serif = elegant or classic; rounded sans = playful; neutral sans = plain, lets other elements carry personality.
   - **Colour:** blue = safe and familiar; gold = expensive, sophisticated; pink = fun, less serious.
   - **Border radius:** none = serious or formal; small = neutral; large = playful. **Never mix square and rounded corners** in one interface.
   - **Language:** impersonal = official; casual = friendly.
7. **Limit your choices. Systematise everything:** font size, weight, line height, colour, margin, padding, width, height, shadows, border radius, border width, opacity. Pick from the system, never ad hoc.
8. **Pick by elimination:** guess a value, compare it with its neighbours on the scale, keep the best, repeat.

## 2. Hierarchy

1. **Not all elements are equal.** De-emphasise secondary and tertiary information on purpose.
2. **Size isn't everything.** Use weight and colour before size.
   - **Text colours: two or three.** Dark for primary content, grey for secondary, lighter grey for tertiary.
   - **Weights: two for UI.** 400 or 500 for most text, 600 or 700 for emphasis. **Never below 400 in UI text** (light weights only for large headings). De-emphasise with colour or size, not a lighter weight.
3. **No grey text on coloured backgrounds.** Don't use white at reduced opacity either (it looks washed out and lets images show through). Hand-pick a colour with the **same hue** as the background and adjust saturation and lightness.
4. **Emphasise by de-emphasising.** If the active item doesn't stand out, soften the competing items. A sidebar competing with content loses its background colour and sits on the page.
5. **Labels are a last resort.**
   - Skip the label when the format says it (email, phone, price) or the context does.
   - Merge label and value: "12 left in stock", "3 bedrooms".
   - When labels are needed (dashboards), make them supporting content: smaller, lower contrast, lighter weight.
   - Emphasise the label only where users scan for it (spec sheets), and then just darken the label slightly.
6. **Visual hierarchy is separate from document hierarchy.** Use `h1`–`h6` for semantics, style them for the hierarchy you need. Section titles often act as labels and should be small. A title can even be visually hidden.
7. **Balance weight and contrast.** Heavy elements (solid icons) get a softer colour. Low-contrast elements (thin soft borders) get more weight (2px instead of 1px) instead of a darker colour.
8. **Semantics are secondary; actions follow a pyramid.**
   - **Primary:** one per page, solid high-contrast background.
   - **Secondary:** outline or low-contrast background.
   - **Tertiary:** styled like links.
   - **Destructive** isn't automatically big and red: use secondary or tertiary style on the page, and the bold red primary style inside the confirmation step.

## 3. Layout and spacing

1. **Start with too much white space, then remove it.** Dense UIs (dashboards) are a deliberate choice, not the default.
2. **Use a spacing and sizing scale** where no two adjacent values are closer than about 25%. Base 16px:

   | px | 4 | 8 | 12 | 16 | 24 | 32 | 48 | 64 | 96 | 128 | 192 | 256 | 384 | 512 | 640 | 768 |
   |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
   | ×16 | 0.25 | 0.5 | 0.75 | 1 | 1.5 | 2 | 3 | 4 | 6 | 8 | 12 | 16 | 24 | 32 | 40 | 48 |
   | Tailwind step | 1 | 2 | 3 | 4 | 6 | 8 | 12 | 16 | 24 | 32 | 48 | 64 | 96 | 128 | 160 | 192 |

   Icon sizes come from the same scale (12, 16, 24, 32).
3. **You don't have to fill the screen.** If something needs 600px, use 600px. Not everything must be full width because the nav is.
4. **Design mobile first** on a ~400px canvas, then adapt for larger screens.
5. **Split into columns rather than stretching.** For example, a narrow form plus a column of supporting text.
6. **Grids are overrated.** Sidebars and other content-optimised elements get a **fixed width**; the main area flexes. Give components a **`max-width`** and shrink them only when the screen is narrower than that, not in grid percentages.
7. **Relative sizing doesn't scale.** Don't tie headline size to body size with `em`. Large elements shrink faster on small screens (e.g. 45px desktop headline next to 18px body becomes 20–24px next to 14px body). Within a component, padding is tuned per size, not proportional: large buttons get more generous padding, small buttons tighter. Example: 16px text, 16px horizontal and 12px vertical padding.
8. **Avoid ambiguous spacing.** **More space around a group than inside it:** label-to-input gap smaller than the gap between form groups; more space above a heading than below; list-item gap bigger than line spacing; the same applies to horizontal groups.

## 4. Text

1. **Hand-crafted type scale** (px, never `em`; use px or rem):

   | px | 12 | 14 | 16 | 18 | 20 | 24 | 30 | 36 | 48 | 60 | 72 |
   |---|---|---|---|---|---|---|---|---|---|---|---|
   | Tailwind | `text-xs` | `text-sm` | `text-base` | `text-lg` | `text-xl` | `text-2xl` | `text-3xl` | `text-4xl` | `text-5xl` | `text-6xl` | `text-7xl` |

   It matches Tailwind's default scale exactly, so use the default classes and no arbitrary sizes. Modular scales (4:5, 2:3, 1:1.618) give fractional or too-sparse sizes for UI; round them if used.
2. **Good fonts:**
   - Safest for UI: a neutral sans, or the system stack `-apple-system, Segoe UI, Roboto, Noto Sans, Ubuntu, Cantarell, Helvetica Neue`.
   - Ignore families with fewer than five weights (filter for 10+ styles to include italics).
   - Optimise for legibility: no condensed, short x-height faces for UI text.
   - Trust popularity; borrow from well-designed sites. Concrete picks are in section 9.
3. **Line length 45–75 characters** (`20em`–`35em`, Tailwind `max-w-prose` = 65ch). Constrain paragraphs even when images beside them are wider.
4. **Baseline, not centre:** align mixed font sizes on one line by their baseline (`items-baseline`).
5. **Line height is proportional.** Narrow text can use 1.5; wide text up to 2. Small text needs taller line height; large headlines can use 1 (`leading-none` / `leading-tight`).
6. **Not every link needs a colour.** In link-heavy UIs, use weight or a darker colour; show ancillary links' underline or colour only on hover. Links inside prose must look clickable.
7. **Alignment:** left-align text in left-to-right languages. Centre only headlines and blocks of two or three lines at most; if a centred block is too long, rewrite it shorter. **Right-align numbers in tables.** Justified text needs `hyphens: auto`.
8. **Letter spacing:** leave it alone by default. **Tighten** headlines set in wide-spaced families (`tracking-tight`). **Widen** all-caps text (`tracking-wide` or more). Never use headline fonts at small sizes.

## 5. Colour

1. **Think in HSL** (hue 0–360°: 0 red, 120 green, 240 blue; saturation; lightness 0 black, 50 pure colour, 100 white). Not HSB.
2. **You need more colours than you think**, in three groups:
   - **Greys:** 8–10 shades. Almost everything is grey. Avoid true black; start from a very dark grey.
   - **Primary:** one or two colours, 5–10 shades each. Ultra-light shades tint backgrounds (alerts); dark shades work as text.
   - **Accents:** highlight colours (yellow, pink, teal) and semantic ones (red = destructive, yellow = warning, green = positive), with multiple shades each. Complex UIs can need ~10 colours × 5–10 shades.
3. **Define shades up front.** Never use `lighten()`/`darken()` or ad hoc variants.
   - Base (500) = a shade that works as a button background.
   - Darkest (900) for text, lightest (100, or 050) for tinted backgrounds. Test both in an alert.
   - Fill 700 and 300 first, then 800, 600, 400, 200. Trust your eyes and tweak, but don't add shades casually.
4. **Don't let lightness kill saturation.** Raise saturation as lightness moves away from 50%.
5. **Use perceived brightness.** `brightness = √(0.299 r² + 0.587 g² + 0.114 b²) / 255`. Bright hues are 60° (yellow), 180° (cyan) and 300° (magenta); dark hues are 0° (red), 120° (green) and 240° (blue). To lighten without washing out, rotate the hue towards the nearest bright hue; to darken, rotate towards the nearest dark hue (e.g. yellow shifts toward orange as it darkens). Rotate at most 20–30°.
6. **Greys can be tinted.** Cool greys: add blue. Warm greys: add yellow or orange. Increase saturation at the lightest and darkest shades to keep the temperature.
7. **Accessible doesn't have to mean ugly.** WCAG: **4.5:1** for normal text (under ~18px), **3:1** for larger text.
   - **Flip the contrast:** dark coloured text on a light tint instead of white on a dark colour, when the element shouldn't dominate.
   - **Coloured text on a coloured background:** rotate the hue toward cyan, magenta or yellow to gain contrast without going white.
8. **Don't rely on colour alone.** Add icons (e.g. up and down arrows on metrics). For charts, vary lightness and contrast, not only hue.

## 6. Depth

1. **Light comes from above.**
   - **Raised element:** a lighter top edge (top border or `inset 0 1px 0 <lighter hand-picked shade>`; the book's blue button uses `hsl(224, 84%, 74%)`) plus a small, sharp dark shadow below: `0 1px 3px hsla(0, 0%, 0%, .2)`. Pick the highlight colour by hand; semi-transparent white kills saturation.
   - **Inset element** (wells, inputs, checkboxes): a lighter bottom lip (bottom border or a shadow with negative vertical offset; the book's dark well uses `0 2px 0 hsla(0, 0%, 100%, .15)`) plus a small dark **inset** shadow with a positive vertical offset at the top.
   - Don't chase realism.
2. **Shadows show elevation; five levels are enough** (exact values from the book):

   | Level | Box shadow | Typical use |
   |---|---|---|
   | 1 | `0 1px 3px hsla(0,0%,0%,.2)` | Buttons |
   | 2 | `0 4px 6px hsla(0,0%,0%,.2)` | Cards |
   | 3 | `0 5px 15px hsla(0,0%,0%,.2)` | Dropdowns, popovers |
   | 4 | `0 10px 24px hsla(0,0%,0%,.2)` | Floating panels |
   | 5 | `0 15px 35px hsla(0,0%,0%,.2)` | Modal dialogs |

   Choose the shadow from where the element sits on the z-axis. Interaction moves along the scale: a dragged item gains a larger shadow; a pressed button drops to a smaller one or none.
3. **Two-part shadows:** a large, soft shadow with a big offset and blur (direct light) plus a tight, darker one with a small offset and blur (ambient occlusion). The tight shadow is distinct at the lowest level and fades to nothing at the highest. The book gives no numbers for this; Tailwind's defaults (`shadow-sm` … `shadow-2xl`) already follow the two-part pattern.
4. **Flat designs still have depth.** Lighter than the background feels raised; darker feels inset. Or use solid shadows: a short vertical offset with zero blur.
5. **Overlap elements to create layers:** a card straddling two background sections, an element taller than its parent, carousel controls overlapping the slide. Overlapping images get an "invisible border" in the background colour.

## 7. Images

1. **Use good photos:** a professional or quality stock (e.g. Unsplash). Never plan to swap placeholders for phone photos later.
2. **Text over images needs consistent contrast:** a semi-transparent overlay (black for light text, white for dark text), a lower-contrast image (compensate brightness), a colourised image (lower contrast → desaturate → solid fill with `multiply`), or a glow-like text shadow (large blur, no offset) combined with a slightly reduced contrast.
3. **Everything has an intended size.** Don't scale up icons drawn for 16–24px; put them inside a shape with a background colour instead. Don't shrink screenshots: capture a smaller layout, crop a partial view, or draw a simplified UI. Redraw favicons at 16px instead of shrinking the logo.
4. **User-uploaded content:** fixed containers with `object-fit: cover` / `background-size: cover`. Prevent background bleed with a subtle **inner box shadow** or a semi-transparent inner border, not a solid border.

## 8. Finishing touches

1. **Supercharge the defaults:** icon bullets (checkmarks, arrows, or domain icons such as a padlock); large coloured quote marks on testimonials; custom link underlines (thick, coloured, partly overlapping the text); custom checkboxes and radios in the brand colour.
2. **Accent borders** add colour without illustration: top of a card, active nav item, side of an alert, a short bar under a headline, top of the whole layout.
3. **Decorate backgrounds:** change the colour of a panel or section; a gradient between two hues **no more than about 30° apart**; a low-contrast repeating pattern (e.g. Hero Patterns), possibly along one edge only; simple shapes or a simplified illustration at low contrast.
4. **Empty states are a priority,** not an afterthought: an illustration plus an emphasised call to action. Hide tabs, filters and other supporting UI that does nothing until content exists.
5. **Use fewer borders.** Separate with a box shadow (when the element differs in colour from the background), two different background colours, or extra spacing.
6. **Think outside the box.** Dropdowns can have sections, columns, supporting text and icons. Table columns that don't need sorting can merge with richer hierarchy, images and colour. Important radio choices can become selectable cards.
7. **Level up:** notice decisions you wouldn't have made, and rebuild interfaces you admire.

### Tailwind v4 mapping

Spacing (4px steps) and the type scale match Tailwind's defaults, so only the shadows need declaring if you want the book's exact elevation scale:

```css
@theme {
  --shadow-1: 0 1px 3px hsla(0, 0%, 0%, .2);
  --shadow-2: 0 4px 6px hsla(0, 0%, 0%, .2);
  --shadow-3: 0 5px 15px hsla(0, 0%, 0%, .2);
  --shadow-4: 0 10px 24px hsla(0, 0%, 0%, .2);
  --shadow-5: 0 15px 35px hsla(0, 0%, 0%, .2);
}
```

Use them as `shadow-1` … `shadow-5` (`ui-tokens.md` §3.3 declares them as softer two-part shadows). Keep `dark:shadow-none` from the directives.

---

## 9. Font recommendations

"Styles" counts weights × italics. Free families are in **bold**.

### Headlines (headline / subtitle / button)

| Headline | Subtitle | Button | Licence |
|---|---|---|---|
| Proxima Nova Bold 48px | Proxima Nova Regular 24px | Proxima Nova Bold 20px | Paid, 8 weights + italics |
| Freight Sans Bold 48px | Proxima Nova Regular 24px | Proxima Nova Bold 20px | Paid, 6 weights + italics |
| Futura Bold 36px | Trade Gothic Next Regular 24px | Trade Gothic Next Bold 20px | Paid, 6 weights + italics |
| Harmonia Sans Black 48px | Graphik Regular 24px | Graphik Semibold 20px | Paid, 5 weights + italics |
| Graphik Black 48px | Graphik Regular 24px | Graphik Semibold 18px | Paid, 9 weights + italics |
| Meta Serif Bold 48px | Myriad Pro Regular 24px | Myriad Pro Semibold 20px | Paid, 6 weights + italics |
| **Roboto Black 48px** | **Roboto Regular 24px** | **Roboto Bold 20px** | **Apache 2.0, Google Fonts, 6 weights + italics** |
| Jubilat Semibold 48px | Proxima Nova Regular 24px | Proxima Nova Bold 20px | Paid, 12 weights + italics |
| Interstate Bold 48px | Interstate Light 24px | Interstate Regular 20px | Paid, 8 weights + italics |
| Neue Plak Extra Black 48px | Neue Plak Regular 24px | Neue Plak Bold 20px | Paid, 7 weights |
| Adelle Extra Bold 48px | Proxima Nova Regular 24px | Proxima Nova Bold 20px | Paid, 7 weights |

### Articles (body / title / meta)

| Body | Title | Meta | Licence |
|---|---|---|---|
| Freight Text Book 18px | Freight Sans Book 48px | Freight Sans Book 16px | Paid |
| **Source Sans Regular 18px** | **Source Sans Light 48px** | **Source Sans Regular 16px** | **OFL, 6 weights + italics** |
| **Open Sans Regular 18px** | **Open Sans Light 48px** | **Open Sans Regular 16px** | **Apache 2.0, Google Fonts, 5 weights + italics** |
| **Merriweather Light 16px** | **Merriweather Sans 16px** | **Merriweather Sans 14px** | **OFL, Google Fonts, 4 weights + italics** |
| Proxima Nova Regular 18px | Freight Sans Bold 48px | Proxima Nova Regular 16px | Paid |
| Franklin Gothic Book 18px | Franklin Gothic Demi 48px | Franklin Gothic Book 16px | Paid |
| Camphor Regular 18px | Camphor Light 48px | Camphor Regular 16px | Paid |

Article pattern: **body 18px** (16px for Merriweather), **meta 16px** (14px), **title 48px**. Light 48px titles appear here; in generated UIs, light display type follows `ui-surfaces.md` (EX-07).

### Application UI (single family for nav, tabs, labels)

| Family | Licence |
|---|---|
| Proxima Nova | Paid, 8 weights + italics |
| **Inter** (shown as "Inter UI") | **SIL OFL 1.1, 12 weights + italics, from rsms.me** |
| **Roboto** | **Apache 2.0, Google Fonts, 6 weights + italics** |
| Graphik | Paid, 9 weights + italics |
| **Source Sans** | **OFL, 6 weights + italics** |
| **Lato** | **OFL, 9 weights + italics (Google Fonts has 10 styles)** |
| Avenir Next | Paid, 8 weights + italics |
| **Open Sans** | **Apache 2.0, Google Fonts, 5 weights + italics** |
| Aktiv Grotesk | Paid, 8 weights + italics |
| Benton Sans | Paid, 8 weights + italics |
| Soleil | Paid, 6 weights + italics |
| Camphor | Paid, 5 weights + italics |
| Neue Plak Text | Paid, 5 weights + italics |
| Effra | Paid, 5 weights + italics |

The generator's current font picks (some newer than this source) are in `ui.md` §2.3; they take precedence over this list. App profiles pick one.

---

## 10. Colour palettes

Each scale has 10 shades, **900 = darkest, 050 = lightest**. The source groups each palette into:
- **Primary:** "splashes of colour that appear the most": primary actions, links, nav items, icons, accent borders, emphasised text.
- **Neutrals:** "the colours you will use the most": most text, backgrounds and borders, secondary buttons and links.
- **Supporting:** used conservatively: to make an element stand out, and for semantic states (errors, positive trends).

In the directives' terms, Primary fills `brand-*`, Neutral fills `grey-*`, the warm supporting scale fills `accent-*` (and `warning-*`), and Red / Green (or Teal) fill `danger-*` / `success-*`. The knowledge base's shade 050 is `50` in the directives.

### 10.1 Palettes

| # | Primary | Neutral | Supporting |
|---|---|---|---|
| 1 | Cyan | Blue Grey | Indigo, Pink, Red, Yellow |
| 2 | Blue, Yellow (Vivid) | Blue Grey | Cyan, Red |
| 3 | Purple (P3), Teal | Blue Grey | Light Blue (Vivid), Red (Vivid), Yellow (Vivid) |
| 4 | Teal | Blue Grey | Blue, Purple, Red, Yellow |
| 5 | *(neutral-led)* | Blue Grey | Light Blue (Vivid), Cyan, Pink (Vivid), Red (Vivid), Yellow (Vivid), Teal |
| 6 | Red, Yellow (Vivid) | Warm Grey | Cyan, Lime Green |
| 7 | Cyan | Warm Grey | Blue, Red, Yellow, Teal |
| 8 | Blue (Vivid) | Cool Grey | Cyan (Vivid), Orange (Vivid), Red (Vivid), Yellow (Vivid) |
| 9 | Light Blue (Vivid) | Cool Grey | Pink (Vivid), Red (Vivid), Yellow (Vivid), Teal |
| 10 | Indigo | Cool Grey | Light Blue (Vivid), Red (Vivid), Yellow (Vivid), Teal |
| 11 | Pink (Vivid) | Cool Grey | Purple (Vivid), Cyan (Vivid), Red (Vivid), Yellow (Vivid) |
| 12 | Green | Grey | Purple, Red, Yellow |
| 13 | Yellow (Vivid), Light Blue (Vivid) | Grey | Red (Vivid), Teal |
| 14 | Orange, Lime Green | Grey | Light Blue, Red, Yellow |
| 15 | Blue | Blue Grey | Teal (Vivid), Red, Yellow |
| 16 | Purple, Red (Vivid) | Blue Grey | Teal (Vivid), Yellow (Vivid) |
| 17 | Magenta, Orange (Vivid) | Blue Grey | Yellow (Vivid), Red (Vivid), Green (Vivid) |
| 18 | Purple | Warm Grey | Cyan, Red (Vivid), Yellow, Green (Vivid) |
| 19 | Indigo, Orange (Vivid) | Cool Grey | Magenta (Vivid), Red (Vivid), Yellow (Vivid), Green (Vivid) |
| 20 | Light Blue, Green | Cool Grey | Purple, Red, Yellow |
| 21 | Orange (Vivid) | Cool Grey | Indigo, Red, Yellow, Green |
| 22 | Indigo, Cyan (Vivid) | Cool Grey | Pink (Vivid), Red (Vivid), Yellow (Vivid), Green (Vivid) |
| 23 | Teal (Vivid) | Grey | Yellow (Vivid), Red (Vivid) |
| 24 | Yellow | Grey | Blue, Orange, Red, Green |

Palette 5 is neutral-led: Blue Grey serves as both primary and neutral ("use the higher contrast shades for your primary actions"). Where a palette has no Green, use Teal for `success`.

### 10.2 Scales

"4.5:1 with white" lists the shades that pass 4.5:1 for white text on the shade, and equally for the shade as text on white. Lighter shades need dark text (use the scale's 800–900).

| Scale | 900 | 800 | 700 | 600 | 500 | 400 | 300 | 200 | 100 | 050 | 4.5:1 with white |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Blue Grey | `#102A43` | `#243B53` | `#334E68` | `#486581` | `#627D98` | `#829AB1` | `#9FB3C8` | `#BCCCDC` | `#D9E2EC` | `#F0F4F8` | 900–600 |
| Cool Grey | `#1F2933` | `#323F4B` | `#3E4C59` | `#52606D` | `#616E7C` | `#7B8794` | `#9AA5B1` | `#CBD2D9` | `#E4E7EB` | `#F5F7FA` | 900–500 |
| Grey | `#222222` | `#3B3B3B` | `#515151` | `#626262` | `#7E7E7E` | `#9E9E9E` | `#B1B1B1` | `#CFCFCF` | `#E1E1E1` | `#F7F7F7` | 900–600 |
| Warm Grey | `#27241D` | `#423D33` | `#504A40` | `#625D52` | `#857F72` | `#A39E93` | `#B8B2A7` | `#D3CEC4` | `#E8E6E1` | `#FAF9F7` | 900–600 |
| Red | `#610404` | `#780A0A` | `#911111` | `#A61B1B` | `#BA2525` | `#D64545` | `#E66A6A` | `#F29B9B` | `#FACDCD` | `#FFEEEE` | 900–500 |
| Red (Vivid) | `#610316` | `#8A041A` | `#AB091E` | `#CF1124` | `#E12D39` | `#EF4E4E` | `#F86A6A` | `#FF9B9B` | `#FFBDBD` | `#FFE3E3` | 900–500 |
| Orange | `#572508` | `#77340D` | `#8C3D10` | `#AB4E19` | `#C65D21` | `#E67635` | `#EF8E58` | `#FAB38B` | `#FFD3BA` | `#FFEFE6` | 900–600 |
| Orange (Vivid) | `#841003` | `#AD1D07` | `#C52707` | `#DE3A11` | `#F35627` | `#F9703E` | `#FF9466` | `#FFB088` | `#FFD0B5` | `#FFE8D9` | 900–700 |
| Yellow | `#513C06` | `#7C5E10` | `#A27C1A` | `#C99A2E` | `#E9B949` | `#F7D070` | `#F9DA8B` | `#F8E3A3` | `#FCEFC7` | `#FFFAEB` | 900–800 |
| Yellow (Vivid) | `#8D2B0B` | `#B44D12` | `#CB6E17` | `#DE911D` | `#F0B429` | `#F7C948` | `#FADB5F` | `#FCE588` | `#FFF3C4` | `#FFFBEA` | 900–800 |
| Lime Green | `#2B4005` | `#42600C` | `#507712` | `#63921A` | `#7BB026` | `#94C843` | `#ABDB5E` | `#C7EA8F` | `#E2F7C2` | `#F2FDE0` | 900–700 |
| Lime Green (Vivid) | `#1E5303` | `#2E7B06` | `#399709` | `#5CB70B` | `#6CD410` | `#8DED2D` | `#AFF75C` | `#CAFF84` | `#E6FFBF` | `#F8FFED` | 900–800 |
| Green | `#05400A` | `#0E5814` | `#207227` | `#2F8132` | `#3F9142` | `#57AE5B` | `#7BC47F` | `#A3D9A5` | `#C1EAC5` | `#E3F9E5` | 900–600 |
| Green (Vivid) | `#014807` | `#07600E` | `#0E7817` | `#0F8613` | `#18981D` | `#31B237` | `#51CA58` | `#91E697` | `#C1F2C7` | `#E3F9E5` | 900–600 |
| Teal | `#014D40` | `#0C6B58` | `#147D64` | `#199473` | `#27AB83` | `#3EBD93` | `#65D6AD` | `#8EEDC7` | `#C6F7E2` | `#EFFCF6` | 900–700 |
| Teal (Vivid) | `#004440` | `#016457` | `#048271` | `#079A82` | `#17B897` | `#2DCCA7` | `#5FE3C0` | `#8EEDD1` | `#C6F7E9` | `#F0FCF9` | 900–700 |
| Cyan | `#044E54` | `#0A6C74` | `#0E7C86` | `#14919B` | `#2CB1BC` | `#38BEC9` | `#54D1DB` | `#87EAF2` | `#BEF8FD` | `#E0FCFF` | 900–700 |
| Cyan (Vivid) | `#05606E` | `#07818F` | `#099AA4` | `#0FB5BA` | `#1CD4D4` | `#3AE7E1` | `#62F4EB` | `#92FDF2` | `#C1FEF6` | `#E1FCF8` | 900–800 |
| Light Blue | `#0B4F71` | `#166086` | `#1D6F98` | `#2D83AE` | `#3994C1` | `#55AAD4` | `#7CC1E4` | `#A7D8F0` | `#D1EEFC` | `#EBF8FF` | 900–700 |
| Light Blue (Vivid) | `#035388` | `#0B69A3` | `#127FBF` | `#1992D4` | `#2BB0ED` | `#40C3F7` | `#5ED0FA` | `#81DEFD` | `#B3ECFF` | `#E3F8FF` | 900–800 |
| Blue | `#003E6B` | `#0A558C` | `#0F609B` | `#186FAF` | `#2680C2` | `#4098D7` | `#62B0E8` | `#84C5F4` | `#B6E0FE` | `#DCEEFB` | 900–600 |
| Blue (Vivid) | `#002159` | `#01337D` | `#03449E` | `#0552B5` | `#0967D2` | `#2186EB` | `#47A3F3` | `#7CC4FA` | `#BAE3FF` | `#E6F6FF` | 900–500 |
| Indigo | `#19216C` | `#2D3A8C` | `#35469C` | `#4055A8` | `#4C63B6` | `#647ACB` | `#7B93DB` | `#98AEEB` | `#BED0F7` | `#E0E8F9` | 900–500 |
| Indigo (Vivid) | `#061178` | `#0B1D96` | `#132DAD` | `#1D3DBF` | `#2251CC` | `#3A66DB` | `#5E8AEE` | `#88B1FC` | `#B0D0FF` | `#D9E8FF` | 900–400 |
| Purple | `#240754` | `#34126F` | `#421987` | `#51279B` | `#653CAD` | `#724BB7` | `#8662C7` | `#A081D9` | `#CFBCF2` | `#EAE2F8` | 900–300 |
| Purple (Vivid) | `#44056E` | `#580A94` | `#690CB0` | `#7A0ECC` | `#8719E0` | `#9446ED` | `#A368FC` | `#B990FF` | `#DAC4FF` | `#F2EBFE` | 900–400 |
| Magenta | `#4E0754` | `#671270` | `#7C1A87` | `#90279C` | `#A23DAD` | `#AD4BB8` | `#BB61C7` | `#CE80D9` | `#ECBDF2` | `#F5E1F7` | 900–400 |
| Magenta (Vivid) | `#6E0560` | `#960888` | `#B30BA3` | `#CB10B8` | `#E019D0` | `#ED47ED` | `#F368FC` | `#F48FFF` | `#F8C4FE` | `#FDEBFF` | 900–600 |
| Pink | `#5C0B33` | `#781244` | `#9B1B5A` | `#AD2167` | `#C42D78` | `#DA4A91` | `#E668A7` | `#F191C1` | `#FAB8D9` | `#FFE0F0` | 900–500 |
| Pink (Vivid) | `#620042` | `#870557` | `#A30664` | `#BC0A6F` | `#DA127D` | `#E8368F` | `#F364A2` | `#FF8CBA` | `#FFB8D2` | `#FFE3EC` | 900–500 |
| Purple (P3) | `#0C008C` | `#1D0EBE` | `#3525E6` | `#4D3DF7` | `#5D55FA` | `#7069FA` | `#8888FC` | `#A2A5FC` | `#C4C6FF` | `#E6E6FF` | 900–500 |

"Purple (P3)" is the distinct purple used only in palette 3; every other palette that says Purple uses the "Purple" row.

---

## 11. Component gallery (variant menu)

The gallery shows greyscale wireframes of named variants. Pick **one variant per component per app** and record it in the app profile, so every screen uses the same one.

- **Buttons:** small rounded, large rounded, full rounded (pill), square; uppercase text; with soft shadow; vertical gradient; horizontal gradient; raised with bottom profile; raised with top profile; icon on left; icon on right. Each has a solid dark primary and three secondary options: A = soft grey fill, B = white with border, C = white with border and a slightly heavier bottom edge.
- **Inputs:** small rounded, full rounded, large rounded, square; thick border; no border; inset shadow; box shadow; bottom border; soft background; soft background with bottom border; bottom border with placeholder label; label inside input; overlapping label; small uppercase label; with icon; with icon and border; icon emphasised; connected inputs with inset labels; connected inputs with placeholder only.
- **Input groups** (field + button): attached, detached, large rounded with inset button, bottom border connected to button, gapped border, full rounded, full rounded with offset button, icon-only button.
- **Error validation:** inline below the input with a solid background; inline connected to the input; inline below with no background; icon with a tooltip on focus; inline right of the input; listed above the form; listed below the form. Example copy: "Oops! An error has occured."
- **Badges:** solid background; soft background; thick soft border; thick soft border and soft background; thin soft border; thin soft border and soft background. Each comes full rounded or small rounded. Also: with icon, with gradient, circle for numbers.
- **Breadcrumbs:** contained with arrows; with icons; with numbers ("01 Home"); home icon only; separated by chevrons (>), dots (•) or slashes (/); with dotted border.
- **Pagination:** numbers with Previous/Next; numbers with chevrons; truncation (…); Previous/Next only, attached or separate; chevron with "Next" text; First/Last buttons or « » chevrons; current page only ("< 2 >"); current of total ("< 2 of 10 >"); thick bottom border on the current page; no borders on numbers; full rounded; no container on inactive pages; thin top or bottom border; circle around the current page; Load more / continuous scroll.
- **Horizontal navigation (tabs):** contained with a light or dark active state; dark raised active; full rounded; full rounded with inset rounded active; lifted active (square or rounded); bottom border with a raised darker active or a thin darker active line; soft rounded active; soft small rounded active; dark small rounded or rounded active; stacked icons; icons; active tab in front with a coloured top border; overlapping tabs with skewed right side.
- **Vertical navigation:** full background highlight; plus left border; plus right border; left border only; right border only; small rounded pill; full rounded pill; bold only; directly on the background; on a panel; on a panel with borders between items; sections separated by whitespace or by a border, with small uppercase section titles ("PERSONAL SETTINGS").
- **Tables:** zebra striping; with borders; condensed; with images; multi-row cells for supporting content; grouping column; grouping row.
- **Sign-in forms:** two-pane with a list, a testimonial or an image; simple card; full page; simple.
- **Alerts:** title bar with description below; soft background with thick border, left icon, title and description; solid background with left icon; full width with left icon; top accent border; left accent border; single line dark; single line soft.
- **Pricing:** single tier (centred, left aligned, horizontal); two tiers (plain or with emphasised plan); three tiers (plain or heavy featured with emphasised plan); four tiers; multi-tier chart; multi-tier table; variable pricing.
- **Marketing heroes:** left text with image right or left; left or centred text over a cover image; centred text with image below or above; right image with right-aligned text; with sign-in form; with newsletter sign-up.
- **Marketing sections:** single feature with image; double feature with icons; feature list with image; triple feature with icons or in cards; single feature horizontal; centred text with image below; multi-feature with stacked icons or left icons; split page; long feature list in columns.
- **Modals:** white or dark shim background; full page; left-aligned buttons; full-width stacked buttons; full-width split buttons.
- **Multi-section forms:** two columns with section label and description on the left; anchor links per section; centred inputs with left labels and borders between sections; left labels with sections in cards; two columns with emphasis on the form; multi-page with horizontal or vertical navigation.
- **Header navigation:** left logo and search with right nav and global actions; left logo and nav with right search and actions; left logo and search, centred nav, right actions; left nav, centred logo, right search and actions; second-row navigation; no background container.
- **Preview cards:** image left / top / right / top inset / thumbnail, combined with an order of Title, Meta, Excerpt and Link (e.g. Image / Meta / Title / Excerpt); "no card" variants; top image with a button or a full-width button; thumbnail with wrapped or indented content.
- **Profile cards:** two columns with labelled sections; with supporting image.
- **Application layouts:** vertical nav overlapping horizontal nav (and the reverse); constrained content with vertical nav; constrained content with full-width horizontal nav; multi-layered side nav; card layout; sidebar only; icon-only sidebar; three columns; secondary right column.
- **Footers:** site map, about, social icons and legal; site map, about, newsletter and legal; logo, about, site map and legal; centred site map with social and legal; logo and newsletter on top; logo, nav, social and legal; legal with stacked nav.
- **Activity feeds:** image with timestamp below or on the right ("1 day ago"); condensed with thumbnail; thumbnails connected with lines; dots connected with lines; alternating sides.
- **Checkout:** user details left with emphasised order summary right (or the reverse with an order table); split page; order table on top with details below; single-product card with image or features.
- **Testimonials:** carousel left-aligned or centred with dotted pagination; with arrows top-left or on the sides; single horizontal layout in a card; stacked layout in a card.
