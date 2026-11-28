defmodule ForkaWeb.E2E.FlashBannerTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: true` because these tests
  # never start a `GameServer` or depend on `"game_list"` broadcasts.
  use ForkaWeb.E2ECase, async: true

  import Ecto.Query

  alias Forka.Games.Schemas.Game
  alias Forka.Repo

  test "AC-01: desktop account menu opens while welcome flash shows in reserved slot, dismiss has zero shift, empty stuck slot is click-through, and scrolled in-place/disconnect errors stick below header",
       %{conn: conn} do
    host = insert(:player, username: "anfitriao")

    room_ids =
      for i <- 1..21 do
        insert(:game, owner: host, name: "Sala #{i}", status: :lobby).id
      end

    player = insert(:player, username: "lia")

    session =
      conn
      |> log_in(player)
      |> assert_has("#rooms-live-status", text: "21 salas")
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

          const groupZ = Number(getComputedStyle(group).zIndex);
          const headerZ = Number(getComputedStyle(header).zIndex);

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
            groupBelowHeaderAndModals: groupZ < headerZ && groupZ < 50
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

          assert layout["groupBelowHeaderAndModals"],
                 "expected #flash-group z-index below header and z-50 modals, got: #{inspect(layout)}"
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

    # Archive the listed rooms directly in the database so clicking an "Entrar"
    # button while scrolled down triggers a real in-place put_flash(:error, ...).
    Repo.update_all(from(g in Game, where: g.id in ^room_ids), set: [status: :archived])

    session
    |> evaluate(
      """
      () => {
        const header = document.querySelector("header");
        const group = document.querySelector("#flash-group");
        const buttons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
        const targetBtn = buttons[6];
        targetBtn.setAttribute("data-test-under-slot", "true");

        const headerHeight = header.getBoundingClientRect().height;
        const btnDocTop = targetBtn.getBoundingClientRect().top + window.scrollY;
        const btnHeight = targetBtn.getBoundingClientRect().height;
        const desiredTopInViewport = headerHeight + Math.max(4, (64 - btnHeight) / 2);
        window.scrollTo(0, Math.round(btnDocTop - desiredTopInViewport));

        const headerRect = header.getBoundingClientRect();
        const groupRect = group.getBoundingClientRect();
        const btnRect = targetBtn.getBoundingClientRect();
        const hitEl = document.elementFromPoint(
          (btnRect.left + btnRect.right) / 2,
          (btnRect.top + btnRect.bottom) / 2
        );

        return {
          scrolledY: window.scrollY,
          slotSticksBelowHeader: Math.abs(groupRect.top - headerRect.bottom) <= 1,
          buttonBehindEmptySlot:
            btnRect.top >= groupRect.top - 1 && btnRect.bottom <= groupRect.bottom + 1,
          emptySlotClickThrough: Boolean(hitEl && targetBtn.contains(hitEl))
        };
      }
      """,
      [is_function: true],
      fn probe ->
        assert probe["scrolledY"] >= 200,
               "expected page to scroll down at least 200px, got: #{inspect(probe)}"

        assert probe["slotSticksBelowHeader"],
               "expected #flash-group to stick directly below header when scrolled, got: #{inspect(probe)}"

        assert probe["buttonBehindEmptySlot"],
               "expected target room button to sit behind empty stuck slot, got: #{inspect(probe)}"

        assert probe["emptySlotClickThrough"],
               "expected content under empty stuck slot to receive pointer events, got: #{inspect(probe)}"
      end
    )
    |> click(~s|button[data-test-under-slot="true"]|)
    |> assert_has("#flash-error", text: "Esta sala foi arquivada.")
    |> click(~s|summary[aria-label="Conta"]|)
    |> assert_has("header details[open]")
    |> evaluate(
      """
      () => {
        const header = document.querySelector("header");
        const dropdown = document.querySelector("header details > div");
        const flashError = document.querySelector("#flash-error");
        const clientError = document.querySelector("#client-error");
        const serverError = document.querySelector("#server-error");

        const headerRect = header.getBoundingClientRect();
        const dropdownRect = dropdown.getBoundingClientRect();
        const errorRect = flashError.getBoundingClientRect();

        const errorHit = document.elementFromPoint(
          errorRect.left + 40,
          (errorRect.top + errorRect.bottom) / 2
        );

        const overlapLeft = Math.max(dropdownRect.left, errorRect.left);
        const overlapRight = Math.min(dropdownRect.right, errorRect.right);
        const overlapTop = Math.max(dropdownRect.top, errorRect.top);
        const overlapBottom = Math.min(dropdownRect.bottom, errorRect.bottom);
        const dropdownHit = document.elementFromPoint(
          (overlapLeft + overlapRight) / 2,
          (overlapTop + overlapBottom) / 2
        );

        // Probe #client-error while scrolled down.
        const prevClientHidden = clientError.hidden;
        const prevClientDisplay = clientError.style.display;
        clientError.hidden = false;
        clientError.style.display = "block";
        const clientRect = clientError.getBoundingClientRect();
        const clientHit = document.elementFromPoint(
          clientRect.left + 40,
          (clientRect.top + clientRect.bottom) / 2
        );
        const dropdownHitOverClient = document.elementFromPoint(
          (overlapLeft + overlapRight) / 2,
          (overlapTop + overlapBottom) / 2
        );
        clientError.hidden = prevClientHidden;
        clientError.style.display = prevClientDisplay;

        // Probe #server-error while scrolled down.
        const prevServerHidden = serverError.hidden;
        const prevServerDisplay = serverError.style.display;
        serverError.hidden = false;
        serverError.style.display = "block";
        const serverRect = serverError.getBoundingClientRect();
        const serverHit = document.elementFromPoint(
          serverRect.left + 40,
          (serverRect.top + serverRect.bottom) / 2
        );
        serverError.hidden = prevServerHidden;
        serverError.style.display = prevServerDisplay;

        return {
          scrolledY: window.scrollY,
          errorBelowHeader:
            Math.abs(errorRect.top - headerRect.bottom) <= 1 &&
            errorRect.bottom <= window.innerHeight,
          errorAboveContent: Boolean(errorHit && flashError.contains(errorHit)),
          dropdownAboveError: Boolean(dropdownHit && dropdown.contains(dropdownHit)),
          clientErrorBelowHeader:
            Math.abs(clientRect.top - headerRect.bottom) <= 1 &&
            clientRect.bottom <= window.innerHeight,
          clientErrorAboveContent: Boolean(clientHit && clientError.contains(clientHit)),
          dropdownAboveClientError: Boolean(
            dropdownHitOverClient && dropdown.contains(dropdownHitOverClient)
          ),
          serverErrorBelowHeader:
            Math.abs(serverRect.top - headerRect.bottom) <= 1 &&
            serverRect.bottom <= window.innerHeight,
          serverErrorAboveContent: Boolean(serverHit && serverError.contains(serverHit))
        };
      }
      """,
      [is_function: true],
      fn probe ->
        assert probe["scrolledY"] >= 200,
               "expected page to stay scrolled after clicking archived room, got: #{inspect(probe)}"

        assert probe["errorBelowHeader"],
               "expected in-place #flash-error visible directly below sticky header after scroll, got: #{inspect(probe)}"

        assert probe["errorAboveContent"],
               "expected in-place #flash-error to sit above scrolled page content, got: #{inspect(probe)}"

        assert probe["dropdownAboveError"],
               "expected open account menu above sticky #flash-error after scroll, got: #{inspect(probe)}"

        assert probe["clientErrorBelowHeader"],
               "expected connection-lost #client-error visible directly below sticky header after scroll, got: #{inspect(probe)}"

        assert probe["clientErrorAboveContent"],
               "expected #client-error to sit above scrolled page content, got: #{inspect(probe)}"

        assert probe["dropdownAboveClientError"],
               "expected open account menu above sticky #client-error after scroll, got: #{inspect(probe)}"

        assert probe["serverErrorBelowHeader"],
               "expected #server-error visible directly below sticky header after scroll, got: #{inspect(probe)}"

        assert probe["serverErrorAboveContent"],
               "expected #server-error to sit above scrolled page content, got: #{inspect(probe)}"
      end
    )
    |> click(~s|summary[aria-label="Conta"]|)
    |> refute_has("header details[open]")
    |> click(~s|#flash-error button[aria-label="fechar"]|)
    |> refute_has("#flash-error")
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

        const paragraph = flash.querySelector("p");
        const range = document.createRange();
        range.selectNodeContents(paragraph);
        const rectsBefore = Array.from(range.getClientRects());
        const lastLineBefore = rectsBefore[rectsBefore.length - 1];
        const fitsInitially =
          Boolean(lastLineBefore) &&
          lastLineBefore.top >= flashRect.top - 1 &&
          lastLineBefore.bottom <= flashRect.bottom + 1;

        const overflowY = getComputedStyle(flash).overflowY;
        const maxScrollTop = flash.scrollHeight - flash.clientHeight;
        let lastLineScrollableIntoView = fitsInitially;

        if (!fitsInitially && maxScrollTop > 0 && (overflowY === "auto" || overflowY === "scroll")) {
          flash.scrollTop = maxScrollTop;
          const rectsAfter = Array.from(range.getClientRects());
          const lastLineAfter = rectsAfter[rectsAfter.length - 1];
          lastLineScrollableIntoView =
            flash.scrollTop > 0 &&
            Boolean(lastLineAfter) &&
            lastLineAfter.top >= flashRect.top - 1 &&
            lastLineAfter.bottom <= flashRect.bottom + 1;
          flash.scrollTop = 0;
        }

        return {
          noBannerHorizontalOverflow: flash.scrollWidth <= flash.clientWidth,
          flashBelowHeader: Math.abs(flashRect.top - headerRect.bottom) <= 1,
          flashBoundedToSlot:
            flashRect.top >= groupRect.top - 1 && flashRect.bottom <= groupRect.bottom + 1,
          flashAboveMain: flashRect.bottom <= mainRect.top + 1,
          flashAboveHeading: flashRect.bottom <= headingRect.top + 1,
          closeButtonInsideBanner:
            closeRect.top >= flashRect.top - 1 && closeRect.bottom <= flashRect.bottom + 1,
          lastLineScrollableIntoView
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

        assert layout["lastLineScrollableIntoView"],
               "expected last line of long notice at 320px to fit or scroll into visible slot, got: #{inspect(layout)}"
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

  test "EDGE-04: headerless /admin/log_in sticks banner at top with no gap when scrolled and keeps empty slot click-through",
       %{conn: conn} do
    conn
    |> visit(~p"/admin/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> type(~s|input[name="admin[email]"]|, "nobody@example.com")
    |> type(~s|input[name="admin[password]"]|, "WrongPassword1!456")
    |> click_button("Log in")
    |> assert_path(~p"/admin/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-error", text: "Invalid email or password")
    |> evaluate(
      """
      () => {
        const main = document.querySelector("main");
        const group = document.querySelector("#flash-group");
        const flashError = document.querySelector("#flash-error");
        const clientError = document.querySelector("#client-error");

        main.style.minHeight = "2000px";
        window.scrollTo(0, 400);

        const groupRect = group.getBoundingClientRect();
        const errorRect = flashError.getBoundingClientRect();
        const errorHit = document.elementFromPoint(
          errorRect.left + 40,
          (errorRect.top + errorRect.bottom) / 2
        );

        const prevHidden = clientError.hidden;
        const prevDisplay = clientError.style.display;
        clientError.hidden = false;
        clientError.style.display = "block";
        const clientRect = clientError.getBoundingClientRect();
        clientError.hidden = prevHidden;
        clientError.style.display = prevDisplay;

        return {
          hasPlayerHeader: Boolean(document.querySelector("header[data-player-header]")),
          scrolledY: window.scrollY,
          groupAtTop: Math.abs(groupRect.top) <= 1,
          errorAtTop: Math.abs(errorRect.top) <= 1,
          errorAboveContent: Boolean(errorHit && flashError.contains(errorHit)),
          clientErrorAtTop: Math.abs(clientRect.top) <= 1
        };
      }
      """,
      [is_function: true],
      fn probe ->
        refute probe["hasPlayerHeader"],
               "expected /admin/log_in not to render player header, got: #{inspect(probe)}"

        assert probe["scrolledY"] >= 300,
               "expected /admin/log_in to scroll down, got: #{inspect(probe)}"

        assert probe["groupAtTop"],
               "expected #flash-group to stick at top: 0 with no gap on /admin/log_in, got: #{inspect(probe)}"

        assert probe["errorAtTop"],
               "expected #flash-error to stick at top: 0 with no gap on /admin/log_in, got: #{inspect(probe)}"

        assert probe["errorAboveContent"],
               "expected #flash-error to paint over scrolled content, got: #{inspect(probe)}"

        assert probe["clientErrorAtTop"],
               "expected #client-error to stick at top: 0 with no gap on /admin/log_in, got: #{inspect(probe)}"
      end
    )
    |> click(~s|#flash-error button[aria-label="close"]|)
    |> refute_has("#flash-error")
    |> evaluate(
      """
      () => {
        const main = document.querySelector("main");
        main.style.minHeight = "2000px";
        const submitBtn = document.querySelector("main form button");
        const btnDocTop = submitBtn.getBoundingClientRect().top + window.scrollY;
        window.scrollTo(0, Math.max(0, Math.round(btnDocTop - 10)));

        const group = document.querySelector("#flash-group");
        const groupRect = group.getBoundingClientRect();
        const btnRect = submitBtn.getBoundingClientRect();
        const hitEl = document.elementFromPoint(
          (btnRect.left + btnRect.right) / 2,
          (btnRect.top + btnRect.bottom) / 2
        );

        return {
          scrolledY: window.scrollY,
          buttonBehindEmptySlot:
            btnRect.top >= groupRect.top - 1 && btnRect.bottom <= groupRect.bottom + 1,
          emptySlotClickThrough: Boolean(hitEl && submitBtn.contains(hitEl))
        };
      }
      """,
      [is_function: true],
      fn probe ->
        assert probe["scrolledY"] > 0,
               "expected /admin/log_in to be scrolled, got: #{inspect(probe)}"

        assert probe["buttonBehindEmptySlot"],
               "expected submit button to sit behind empty stuck slot, got: #{inspect(probe)}"

        assert probe["emptySlotClickThrough"],
               "expected content under empty stuck slot on /admin/log_in to be clickable, got: #{inspect(probe)}"
      end
    )
  end
end
