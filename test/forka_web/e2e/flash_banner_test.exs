defmodule ForkaWeb.E2E.FlashBannerTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: true` because these tests
  # never create a room, start a `GameServer`, or depend on `"game_list"`
  # broadcasts.
  use ForkaWeb.E2ECase, async: true

  test "AC-01: desktop account menu opens while welcome flash shows in reserved slot with no overlap, priority stacking, non-sticky scroll, and zero layout shift on dismiss",
       %{conn: conn} do
    player = insert(:player, username: "lia")

    conn
    |> log_in(player)
    |> assert_has("#flash-info", text: "Bem-vindo de volta!")
    |> click(~s|summary[aria-label="Conta"]|)
    |> assert_has("header details[open]")
    |> assert_has("header details", text: "Minha conta")
    |> assert_has("header details", text: "Sair")
    |> evaluate(
      """
      () => {
        const header = document.querySelector("header");
        const summary = document.querySelector('summary[aria-label="Conta"]');
        const dropdown = document.querySelector("header details > div");
        const group = document.querySelector("#flash-group");
        const flash = document.querySelector("#flash-info");
        const clientError = document.querySelector("#client-error");
        const main = document.querySelector("main");
        const heading = document.querySelector("main h1");

        const headerRect = header.getBoundingClientRect();
        const summaryRect = summary.getBoundingClientRect();
        const dropdownRect = dropdown.getBoundingClientRect();
        const groupRect = group.getBoundingClientRect();
        const flashRect = flash.getBoundingClientRect();
        const mainRect = main.getBoundingClientRect();
        const headingRect = heading.getBoundingClientRect();

        window.__forkaBeforeDismiss = {
          groupHeight: Math.round(groupRect.height),
          mainTop: Math.round(mainRect.top),
          headingTop: Math.round(headingRect.top)
        };

        const overlapLeft = Math.max(dropdownRect.left, flashRect.left);
        const overlapRight = Math.min(dropdownRect.right, flashRect.right);
        const overlapTop = Math.max(dropdownRect.top, flashRect.top);
        const overlapBottom = Math.min(dropdownRect.bottom, flashRect.bottom);
        const topElAtDropdown = document.elementFromPoint(
          (overlapLeft + overlapRight) / 2,
          (overlapTop + overlapBottom) / 2
        );

        // Temporarily unhide #client-error to prove simultaneous flashes share the
        // same slot with zero layout shift and #client-error draws above #flash-info.
        const prevHidden = clientError.hidden;
        const prevDisplay = clientError.style.display;
        clientError.hidden = false;
        clientError.style.display = "block";
        const groupHeightWithBoth = Math.round(group.getBoundingClientRect().height);
        const mainTopWithBoth = Math.round(main.getBoundingClientRect().top);
        const topElAtSlotLeft = document.elementFromPoint(
          flashRect.left + 40,
          (flashRect.top + flashRect.bottom) / 2
        );
        clientError.hidden = prevHidden;
        clientError.style.display = prevDisplay;

        // Verify normal-flow (non-sticky) behaviour when scrolling a tall page.
        main.style.minHeight = "2000px";
        window.scrollTo(0, 400);
        const scrolledY = window.scrollY;
        const scrolledHeaderRect = header.getBoundingClientRect();
        const scrolledFlashRect = flash.getBoundingClientRect();
        window.scrollTo(0, 0);
        main.style.minHeight = "";

        return {
          flashBelowHeader: Math.abs(flashRect.top - headerRect.bottom) <= 1,
          flashClearsAccountButton: flashRect.top >= summaryRect.bottom - 1,
          flashFitsSlot: Math.round(flashRect.height) === Math.round(groupRect.height),
          flashAboveMain: flashRect.bottom <= mainRect.top + 1,
          flashAboveHeading: flashRect.bottom <= headingRect.top + 1,
          dropdownOverlapsFlash: overlapRight > overlapLeft && overlapBottom > overlapTop,
          dropdownAboveFlash: Boolean(topElAtDropdown && dropdown.contains(topElAtDropdown)),
          slotStableWithTwoFlashes:
            groupHeightWithBoth === Math.round(groupRect.height) &&
            mainTopWithBoth === Math.round(mainRect.top),
          clientErrorAboveInfo: Boolean(topElAtSlotLeft && clientError.contains(topElAtSlotLeft)),
          scrolled: scrolledY >= 300,
          flashScrollsAway: scrolledFlashRect.bottom <= scrolledHeaderRect.bottom + 1
        };
      }
      """,
      [is_function: true],
      fn layout ->
        assert layout["flashBelowHeader"],
               "expected #flash-info directly below header, got: #{inspect(layout)}"

        assert layout["flashClearsAccountButton"],
               "expected #flash-info below Conta button, got: #{inspect(layout)}"

        assert layout["flashFitsSlot"],
               "expected #flash-info to fit inside #flash-group slot, got: #{inspect(layout)}"

        assert layout["flashAboveMain"],
               "expected #flash-info not to overlap main, got: #{inspect(layout)}"

        assert layout["flashAboveHeading"],
               "expected #flash-info not to overlap page heading, got: #{inspect(layout)}"

        assert layout["dropdownOverlapsFlash"],
               "expected open dropdown to intersect banner, got: #{inspect(layout)}"

        assert layout["dropdownAboveFlash"],
               "expected open dropdown above banner, got: #{inspect(layout)}"

        assert layout["slotStableWithTwoFlashes"],
               "expected simultaneous flashes not to grow slot or shift main, got: #{inspect(layout)}"

        assert layout["clientErrorAboveInfo"],
               "expected #client-error to draw above #flash-info in shared slot, got: #{inspect(layout)}"

        assert layout["scrolled"], "expected page to scroll, got: #{inspect(layout)}"

        assert layout["flashScrollsAway"],
               "expected non-sticky banner to scroll away with page, got: #{inspect(layout)}"
      end
    )
    |> click(~s|summary[aria-label="Conta"]|)
    |> refute_has("header details[open]")
    |> click(~s|#flash-info button[aria-label="fechar"]|)
    |> refute_has("#flash-info")
    |> evaluate(
      """
      () => {
        const group = document.querySelector("#flash-group");
        const main = document.querySelector("main");
        const heading = document.querySelector("main h1");
        return {
          before: window.__forkaBeforeDismiss,
          after: {
            groupHeight: Math.round(group.getBoundingClientRect().height),
            mainTop: Math.round(main.getBoundingClientRect().top),
            headingTop: Math.round(heading.getBoundingClientRect().top)
          }
        };
      }
      """,
      [is_function: true],
      fn %{
           "before" => before_dismiss,
           "after" => after_dismiss
         } ->
        assert after_dismiss["groupHeight"] == 64,
               "expected reserved desktop slot height 64px after dismiss, got: #{inspect(after_dismiss)}"

        assert after_dismiss == before_dismiss,
               "expected zero layout shift after dismiss (before: #{inspect(before_dismiss)}, after: #{inspect(after_dismiss)})"
      end
    )
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}, is_mobile: true]
  test "AC-02: mobile (390x844) account menu opens while welcome flash shows in reserved slot with no overlap and zero layout shift on dismiss",
       %{conn: conn} do
    player = insert(:player, username: "bruno")

    conn
    |> log_in(player)
    |> evaluate("window.innerWidth", &assert(&1 == 390))
    |> assert_has("#flash-info", text: "Bem-vindo de volta!")
    |> click(~s|summary[aria-label="Conta"]|)
    |> assert_has("header details[open]")
    |> assert_has("header details", text: "Minha conta")
    |> assert_has("header details", text: "Sair")
    |> evaluate(
      """
      () => {
        const header = document.querySelector("header");
        const dropdown = document.querySelector("header details > div");
        const group = document.querySelector("#flash-group");
        const flash = document.querySelector("#flash-info");
        const main = document.querySelector("main");
        const heading = document.querySelector("main h1");

        const headerRect = header.getBoundingClientRect();
        const dropdownRect = dropdown.getBoundingClientRect();
        const groupRect = group.getBoundingClientRect();
        const flashRect = flash.getBoundingClientRect();
        const mainRect = main.getBoundingClientRect();
        const headingRect = heading.getBoundingClientRect();

        window.__forkaMobileBeforeDismiss = {
          groupHeight: Math.round(groupRect.height),
          mainTop: Math.round(mainRect.top),
          headingTop: Math.round(headingRect.top)
        };

        const overlapLeft = Math.max(dropdownRect.left, flashRect.left);
        const overlapRight = Math.min(dropdownRect.right, flashRect.right);
        const overlapTop = Math.max(dropdownRect.top, flashRect.top);
        const overlapBottom = Math.min(dropdownRect.bottom, flashRect.bottom);
        const topElAtDropdown = document.elementFromPoint(
          (overlapLeft + overlapRight) / 2,
          (overlapTop + overlapBottom) / 2
        );

        return {
          noHorizontalOverflow: document.documentElement.scrollWidth <= window.innerWidth,
          flashBelowHeader: Math.abs(flashRect.top - headerRect.bottom) <= 1,
          flashFitsSlot: Math.round(flashRect.height) === Math.round(groupRect.height),
          flashAboveMain: flashRect.bottom <= mainRect.top + 1,
          flashAboveHeading: flashRect.bottom <= headingRect.top + 1,
          dropdownOverlapsFlash: overlapRight > overlapLeft && overlapBottom > overlapTop,
          dropdownAboveFlash: Boolean(topElAtDropdown && dropdown.contains(topElAtDropdown))
        };
      }
      """,
      [is_function: true],
      fn layout ->
        assert layout["noHorizontalOverflow"],
               "expected no horizontal overflow at 390px, got: #{inspect(layout)}"

        assert layout["flashBelowHeader"],
               "expected #flash-info directly below header on mobile, got: #{inspect(layout)}"

        assert layout["flashFitsSlot"],
               "expected #flash-info to fit inside #flash-group slot on mobile, got: #{inspect(layout)}"

        assert layout["flashAboveMain"],
               "expected #flash-info not to overlap main on mobile, got: #{inspect(layout)}"

        assert layout["flashAboveHeading"],
               "expected #flash-info not to overlap page heading on mobile, got: #{inspect(layout)}"

        assert layout["dropdownOverlapsFlash"],
               "expected open dropdown to intersect banner on mobile, got: #{inspect(layout)}"

        assert layout["dropdownAboveFlash"],
               "expected open dropdown above banner on mobile, got: #{inspect(layout)}"
      end
    )
    |> click(~s|summary[aria-label="Conta"]|)
    |> refute_has("header details[open]")
    |> click(~s|#flash-info button[aria-label="fechar"]|)
    |> refute_has("#flash-info")
    |> evaluate(
      """
      () => {
        const group = document.querySelector("#flash-group");
        const main = document.querySelector("main");
        const heading = document.querySelector("main h1");
        return {
          before: window.__forkaMobileBeforeDismiss,
          after: {
            groupHeight: Math.round(group.getBoundingClientRect().height),
            mainTop: Math.round(main.getBoundingClientRect().top),
            headingTop: Math.round(heading.getBoundingClientRect().top)
          }
        };
      }
      """,
      [is_function: true],
      fn %{
           "before" => before_dismiss,
           "after" => after_dismiss
         } ->
        assert after_dismiss["groupHeight"] == 96,
               "expected reserved mobile slot height 96px after dismiss, got: #{inspect(after_dismiss)}"

        assert after_dismiss == before_dismiss,
               "expected zero layout shift on mobile after dismiss (before: #{inspect(before_dismiss)}, after: #{inspect(after_dismiss)})"
      end
    )
  end

  @tag browser_context_opts: [viewport: %{width: 320, height: 568}, is_mobile: true]
  test "EDGE-03: longest flash message at 320px stays strictly inside the reserved slot without spilling onto content or shifting it",
       %{conn: conn} do
    conn
    |> visit(~p"/admin/confirm")
    |> assert_has("[data-phx-main].phx-connected")
    |> evaluate("window.innerWidth", &assert(&1 == 320))
    |> type(~s|input[name="admin[email]"]|, "nobody@example.com")
    |> click_button("Resend confirmation instructions")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
    |> assert_has(
      "#flash-info",
      text:
        "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."
    )
    |> evaluate(
      """
      () => {
        const header = document.querySelector("header");
        const group = document.querySelector("#flash-group");
        const flash = document.querySelector("#flash-info");
        const closeBtn = document.querySelector('#flash-info button[aria-label="fechar"]');
        const main = document.querySelector("main");
        const heading = document.querySelector("main h1");

        const headerRect = header.getBoundingClientRect();
        const groupRect = group.getBoundingClientRect();
        const flashRect = flash.getBoundingClientRect();
        const closeRect = closeBtn.getBoundingClientRect();
        const mainRect = main.getBoundingClientRect();
        const headingRect = heading.getBoundingClientRect();

        window.__forka320BeforeDismiss = {
          groupHeight: Math.round(groupRect.height),
          mainTop: Math.round(mainRect.top),
          headingTop: Math.round(headingRect.top)
        };

        return {
          noBannerHorizontalOverflow: flash.scrollWidth <= flash.clientWidth,
          flashBelowHeader: Math.abs(flashRect.top - headerRect.bottom) <= 1,
          flashBoundedToSlot:
            flashRect.top >= groupRect.top - 1 && flashRect.bottom <= groupRect.bottom + 1,
          flashAboveMain: flashRect.bottom <= mainRect.top + 1,
          flashAboveHeading: flashRect.bottom <= headingRect.top + 1,
          closeButtonInsideBanner:
            closeRect.top >= flashRect.top - 1 && closeRect.bottom <= flashRect.bottom + 1
        };
      }
      """,
      [is_function: true],
      fn layout ->
        assert layout["noBannerHorizontalOverflow"],
               "expected no horizontal overflow inside banner at 320px, got: #{inspect(layout)}"

        assert layout["flashBelowHeader"],
               "expected #flash-info directly below header at 320px, got: #{inspect(layout)}"

        assert layout["flashBoundedToSlot"],
               "expected #flash-info not to spill past #flash-group slot at 320px, got: #{inspect(layout)}"

        assert layout["flashAboveMain"],
               "expected #flash-info not to overlap main at 320px, got: #{inspect(layout)}"

        assert layout["flashAboveHeading"],
               "expected #flash-info not to overlap page heading at 320px, got: #{inspect(layout)}"

        assert layout["closeButtonInsideBanner"],
               "expected close button visible inside banner at 320px, got: #{inspect(layout)}"
      end
    )
    |> click(~s|#flash-info button[aria-label="fechar"]|)
    |> refute_has("#flash-info")
    |> evaluate(
      """
      () => {
        const group = document.querySelector("#flash-group");
        const main = document.querySelector("main");
        const heading = document.querySelector("main h1");
        return {
          before: window.__forka320BeforeDismiss,
          after: {
            groupHeight: Math.round(group.getBoundingClientRect().height),
            mainTop: Math.round(main.getBoundingClientRect().top),
            headingTop: Math.round(heading.getBoundingClientRect().top)
          }
        };
      }
      """,
      [is_function: true],
      fn %{
           "before" => before_dismiss,
           "after" => after_dismiss
         } ->
        assert after_dismiss["groupHeight"] == 96,
               "expected reserved 320px slot height 96px after dismiss, got: #{inspect(after_dismiss)}"

        assert after_dismiss == before_dismiss,
               "expected zero layout shift at 320px after dismiss (before: #{inspect(before_dismiss)}, after: #{inspect(after_dismiss)})"
      end
    )
  end
end
