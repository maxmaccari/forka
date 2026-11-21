# UI Directives: colour palettes

Reference for the UI directives (`.agents/rules/ui.md`); not always-on. Read it when picking or swapping a palette. The app's `ui-profile.md` records the choice.

## Appendix A. Refactoring UI colour palettes

Pick one palette per app. **Primary** fills `brand`, **Neutral** fills `grey`, the warm supporting scale fills `accent` / `warning`, and the red and green (or teal) supporting scales fill `danger` / `success`. If a palette lacks one of these, borrow the scale from another palette and say so in the profile.

| # | Primary | Neutral | Supporting |
|---|---|---|---|
| 1 | Cyan | Blue Grey | Indigo, Pink, Red, Yellow |
| 2 | Blue, Yellow (Vivid) | Blue Grey | Cyan, Red |
| 3 | Purple (P3), Teal | Blue Grey | Light Blue (Vivid), Red (Vivid), Yellow (Vivid) |
| 4 | Teal | Blue Grey | Blue, Purple, Red, Yellow |
| 5 | *(neutral-led: Blue Grey's dark shades as primary)* | Blue Grey | Light Blue (Vivid), Cyan, Pink (Vivid), Red (Vivid), Yellow (Vivid), Teal |
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

**Scales** (hex as published; convert to HSL for `@theme`). The last column lists the shades that pass 4.5:1 with white, both as a fill under white text and as text on white.

| Scale | 900 | 800 | 700 | 600 | 500 | 400 | 300 | 200 | 100 | 50 | 4.5:1 with white |
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

"Purple (P3)" is used only in palette 3; every other palette that says Purple uses the "Purple" row.
