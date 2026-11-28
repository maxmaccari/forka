defmodule ForkaWeb.E2E.FlashBannerTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: true` because these tests
  # never start a `GameServer` or depend on `"game_list"` broadcasts.
  use ForkaWeb.E2ECase, async: true

  import Ecto.Query

  alias Forka.Games.Schemas.Game
  alias Forka.Repo
  alias PhoenixTest.Playwright.Config
  alias PlaywrightEx.{Connection, Page, Route, Supervisor}

  test "AC-01: desktop account menu opens while welcome flash shows in reserved slot, dismiss has zero shift, empty stuck slot is click-through, and scrolled in-place and real disconnect errors stick below header",
       %{conn: conn} do
    host = insert(:player, username: "anfitriao")

    rooms =
      for i <- 1..21 do
        name = "Sala #{String.pad_leading(Integer.to_string(i), 2, "0")}"
        insert(:game, owner: host, name: name, status: :lobby)
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

    # Pick one listed room midway down the directory and archive only that room
    # in the database so clicking it while scrolled triggers a real in-place
    # put_flash(:error, ...) while keeping 20 open rooms for the reconnect check.
    session =
      evaluate(
        session,
        """
        () => {
          const buttons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
          const targetBtn = buttons[6];
          targetBtn.setAttribute("data-test-under-slot", "true");
          return targetBtn.getAttribute("phx-value-id");
        }
        """,
        [is_function: true],
        fn target_id ->
          assert Enum.any?(rooms, &(&1.id == target_id))
          Repo.update_all(from(g in Game, where: g.id == ^target_id), set: [status: :archived])
        end
      )

    session =
      session
      |> evaluate(
        """
        () => {
          const header = document.querySelector("header");
          const group = document.querySelector("#flash-group");
          const targetBtn = document.querySelector('button[data-test-under-slot="true"]');

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

          return {
            scrolledY: window.scrollY,
            errorBelowHeader:
              Math.abs(errorRect.top - headerRect.bottom) <= 1 &&
              errorRect.bottom <= window.innerHeight,
            errorAboveContent: Boolean(errorHit && flashError.contains(errorHit)),
            dropdownAboveError: Boolean(dropdownHit && dropdown.contains(dropdownHit))
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
        end
      )
      |> click(~s|summary[aria-label="Conta"]|)
      |> refute_has("header details[open]")

    # Trigger a REAL WebSocket close while scrolled down and #flash-error is still
    # visible, gating socket retries and blocking the LongPoll fallback so the
    # disconnect notice renders genuinely without any attribute/style overrides.
    timeout = Config.global(:timeout)
    page_id = session.page_id

    {:ok, _} =
      Page.route(
        page_id,
        "**/live/longpoll*",
        fn route, _request ->
          {:ok, _} = Route.abort(route, error_code: "failed")
        end,
        timeout: timeout
      )

    try do
      session
      |> evaluate(
        """
        () => {
          const group = document.querySelector("#flash-group");
          const main = document.querySelector("main");
          const clientError = document.querySelector("#client-error");
          const roomButtons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
          const alreadyFocused = roomButtons[6];
          alreadyFocused.focus({ preventScroll: true });

          window.__forkaSameDoc = true;
          window.__forkaClientErrorHideStarted = false;
          clientError.addEventListener("phx:hide-start", () => {
            window.__forkaClientErrorHideStarted = true;
          });

          window.__forkaBeforeDisconnect = {
            scrollY: Math.round(window.scrollY),
            groupHeight: Math.round(group.getBoundingClientRect().height),
            mainTop: Math.round(main.getBoundingClientRect().top)
          };

          const socket = window.liveSocket.socket;
          const isWebSocket = socket.conn instanceof WebSocket;
          socket.cancelFallback();
          window.__forkaRestoreReconnect = {
            timerCalc: socket.reconnectTimer.timerCalc,
            longPollFallbackMs: socket.longPollFallbackMs
          };
          socket.longPollFallbackMs = undefined;
          socket.reconnectTimer.timerCalc = () => 60000;
          socket.conn.close();

          return { isWebSocket };
        }
        """,
        [is_function: true],
        fn result ->
          assert result["isWebSocket"],
                 "expected an active WebSocket transport before disconnect, got: #{inspect(result)}"
        end
      )
      |> assert_has("[data-phx-main].phx-client-error")
      |> assert_has("#client-error", text: "Sem conexão com a internet")
      |> assert_has("#client-error", text: "Tentando reconectar")
      |> refute_has("#client-error button")
      |> click(~s|summary[aria-label="Conta"]|)
      |> assert_has("header details[open]")
      |> evaluate(
        """
        () => {
          const header = document.querySelector("header");
          const dropdown = document.querySelector("header details > div");
          const group = document.querySelector("#flash-group");
          const main = document.querySelector("main");
          const clientError = document.querySelector("#client-error");

          const headerRect = header.getBoundingClientRect();
          const dropdownRect = dropdown.getBoundingClientRect();
          const clientRect = clientError.getBoundingClientRect();
          const clientStyle = getComputedStyle(clientError);

          const clientHit = document.elementFromPoint(
            clientRect.left + 40,
            (clientRect.top + clientRect.bottom) / 2
          );

          const overlapLeft = Math.max(dropdownRect.left, clientRect.left);
          const overlapRight = Math.min(dropdownRect.right, clientRect.right);
          const overlapTop = Math.max(dropdownRect.top, clientRect.top);
          const overlapBottom = Math.min(dropdownRect.bottom, clientRect.bottom);
          const dropdownHit = document.elementFromPoint(
            (overlapLeft + overlapRight) / 2,
            (overlapTop + overlapBottom) / 2
          );

          return {
            before: window.__forkaBeforeDisconnect,
            after: {
              scrollY: Math.round(window.scrollY),
              groupHeight: Math.round(group.getBoundingClientRect().height),
              mainTop: Math.round(main.getBoundingClientRect().top)
            },
            disconnected: !window.liveSocket.isConnected(),
            hasHiddenAttr: clientError.hasAttribute("hidden"),
            hasPhxClick: clientError.hasAttribute("phx-click"),
            cursor: clientStyle.cursor,
            computedDisplay: clientStyle.display,
            clientErrorPainted: clientRect.width > 0 && clientRect.height > 0,
            clientErrorBelowHeader:
              Math.abs(clientRect.top - headerRect.bottom) <= 1 &&
              clientRect.bottom <= window.innerHeight,
            clientErrorAboveFlashAndContent: Boolean(clientHit && clientError.contains(clientHit)),
            dropdownAboveClientError: Boolean(dropdownHit && dropdown.contains(dropdownHit))
          };
        }
        """,
        [is_function: true],
        fn probe ->
          assert probe["disconnected"],
                 "expected socket to remain disconnected while gated, got: #{inspect(probe)}"

          refute probe["hasHiddenAttr"],
                 "expected #client-error not to carry HTML hidden attribute, got: #{inspect(probe)}"

          refute probe["hasPhxClick"],
                 "expected #client-error not to carry phx-click, got: #{inspect(probe)}"

          refute probe["cursor"] == "pointer",
                 "expected #client-error not to use pointer cursor, got: #{inspect(probe)}"

          assert probe["computedDisplay"] != "none" and probe["clientErrorPainted"],
                 "expected #client-error to be genuinely painted, got: #{inspect(probe)}"

          assert probe["clientErrorBelowHeader"],
                 "expected #client-error painted directly below sticky header while scrolled, got: #{inspect(probe)}"

          assert probe["clientErrorAboveFlashAndContent"],
                 "expected #client-error to paint above #flash-error and scrolled page content, got: #{inspect(probe)}"

          assert probe["dropdownAboveClientError"],
                 "expected open account menu above sticky #client-error, got: #{inspect(probe)}"

          assert probe["after"] == probe["before"],
                 "expected no layout or scroll shift when #client-error appeared over already-focused control (before: #{inspect(probe["before"])}, after: #{inspect(probe["after"])})"
        end
      )
      |> click(~s|summary[aria-label="Conta"]|)
      |> refute_has("header details[open]")
      |> click("#client-error")
      |> assert_has("#client-error", text: "Tentando reconectar")
      |> evaluate(
        """
        () => new Promise((resolve) => {
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              const header = document.querySelector("header");
              const clientError = document.querySelector("#client-error");
              const headerRect = header.getBoundingClientRect();
              const clientRect = clientError.getBoundingClientRect();
              resolve({
                disconnected: !window.liveSocket.isConnected(),
                hideStarted: window.__forkaClientErrorHideStarted,
                computedDisplay: getComputedStyle(clientError).display,
                stillBelowHeader:
                  clientRect.height > 0 && Math.abs(clientRect.top - headerRect.bottom) <= 1
              });
            });
          });
        })
        """,
        [is_function: true],
        fn probe ->
          assert probe["disconnected"],
                 "expected socket to stay disconnected after clicking #client-error, got: #{inspect(probe)}"

          refute probe["hideStarted"],
                 "expected clicking #client-error while offline not to trigger hide_flash, got: #{inspect(probe)}"

          assert probe["computedDisplay"] != "none" and probe["stillBelowHeader"],
                 "expected #client-error to remain painted below header after click, got: #{inspect(probe)}"
        end
      )
      |> evaluate(
        """
        () => {
          const socket = window.liveSocket.socket;
          const saved = window.__forkaRestoreReconnect;
          socket.reconnectTimer.timerCalc = saved.timerCalc;
          socket.longPollFallbackMs = saved.longPollFallbackMs;
          socket.reconnectTimer.reset();
          socket.reconnectTimer.scheduleTimeout();
        }
        """,
        is_function: true
      )
      |> assert_has("[data-phx-main].phx-connected")
      |> refute_has("#client-error")
      |> assert_has("#rooms-live-status", text: "20 salas")
      |> evaluate(
        """
        () => {
          const header = document.querySelector("header");
          const group = document.querySelector("#flash-group");
          const clientError = document.querySelector("#client-error");
          const buttons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
          const targetBtn = buttons[6];

          const headerHeight = header.getBoundingClientRect().height;
          const btnDocTop = targetBtn.getBoundingClientRect().top + window.scrollY;
          const btnHeight = targetBtn.getBoundingClientRect().height;
          window.scrollTo(0, Math.round(btnDocTop - (headerHeight + Math.max(4, (64 - btnHeight) / 2))));

          const groupRect = group.getBoundingClientRect();
          const btnRect = targetBtn.getBoundingClientRect();
          const hitEl = document.elementFromPoint(
            (btnRect.left + btnRect.right) / 2,
            (btnRect.top + btnRect.bottom) / 2
          );
          const conn = window.liveSocket.socket.conn;

          return {
            sameDocument: window.__forkaSameDoc === true,
            reconnectedWebSocket: Boolean(conn instanceof WebSocket && conn.readyState === WebSocket.OPEN),
            clientErrorHidden: getComputedStyle(clientError).display === "none",
            buttonBehindEmptySlot:
              btnRect.top >= groupRect.top - 1 && btnRect.bottom <= groupRect.bottom + 1,
            emptySlotClickThrough: Boolean(hitEl && targetBtn.contains(hitEl))
          };
        }
        """,
        [is_function: true],
        fn probe ->
          assert probe["sameDocument"],
                 "expected genuine LiveView rejoin in the same document, got: #{inspect(probe)}"

          assert probe["reconnectedWebSocket"],
                 "expected rejoined transport to be an open WebSocket, got: #{inspect(probe)}"

          assert probe["clientErrorHidden"],
                 "expected #client-error to be hidden after rejoin, got: #{inspect(probe)}"

          assert probe["buttonBehindEmptySlot"] and probe["emptySlotClickThrough"],
                 "expected empty stuck slot to pass clicks through after rejoin, got: #{inspect(probe)}"
        end
      )
    after
      {:ok, _} = Page.unroute_all(page_id, timeout: timeout)
    end
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

        main.style.minHeight = "2000px";
        window.scrollTo(0, 400);

        const groupRect = group.getBoundingClientRect();
        const errorRect = flashError.getBoundingClientRect();
        const errorHit = document.elementFromPoint(
          errorRect.left + 40,
          (errorRect.top + errorRect.bottom) / 2
        );

        return {
          hasPlayerHeader: Boolean(document.querySelector("header[data-player-header]")),
          scrolledY: window.scrollY,
          groupAtTop: Math.abs(groupRect.top) <= 1,
          errorAtTop: Math.abs(errorRect.top) <= 1,
          errorAboveContent: Boolean(errorHit && flashError.contains(errorHit))
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

  test "EDGE-05: desktop Tab and Shift+Tab reveal newly keyboard-focused controls below a sticky flash banner",
       %{conn: conn} do
    assert_keyboard_focus_clears_sticky_banner(conn, forward_start: 5, reverse_start: 9)
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}, is_mobile: true]
  test "EDGE-06: mobile (390x844) Tab and Shift+Tab reveal newly keyboard-focused controls below a sticky flash banner",
       %{conn: conn} do
    assert_keyboard_focus_clears_sticky_banner(conn, forward_start: 5, reverse_start: 7)
  end

  defp assert_keyboard_focus_clears_sticky_banner(conn, opts) do
    forward_start = Keyword.fetch!(opts, :forward_start)
    forward_dest = forward_start + 1
    reverse_start = Keyword.fetch!(opts, :reverse_start)
    reverse_dest = reverse_start - 1

    host = insert(:player, username: "anfitriao")

    rooms =
      for i <- 1..21 do
        name = "Sala #{String.pad_leading(Integer.to_string(i), 2, "0")}"
        insert(:game, owner: host, name: name, status: :lobby)
      end

    player = insert(:player, username: "lia")

    session =
      conn
      |> log_in(player)
      |> assert_has("#rooms-live-status", text: "21 salas")
      |> assert_has("#flash-info", text: "Bem-vindo de volta!")
      |> click(~s|#flash-info button[aria-label="fechar"]|)
      |> refute_has("#flash-info")

    # Archive only the first displayed room so clicking its button produces a real
    # in-place #flash-error while keeping 20 scrollable rooms in the directory.
    session =
      evaluate(
        session,
        """
        () => {
          const firstBtn = document.querySelector('#rooms-list button[phx-click="join_room"]');
          firstBtn.setAttribute("data-test-stale-room", "true");
          return firstBtn.getAttribute("phx-value-id");
        }
        """,
        [is_function: true],
        fn stale_id ->
          assert Enum.any?(rooms, &(&1.id == stale_id))
          Repo.update_all(from(g in Game, where: g.id == ^stale_id), set: [status: :archived])
        end
      )
      |> click(~s|button[data-test-stale-room="true"]|)
      |> assert_has("#flash-error", text: "Esta sala foi arquivada.")

    # Forward Tab: reach forward_start via native Tab from the exposed Conta button,
    # scroll so forward_dest sits completely beneath #flash-error inside the viewport,
    # then press real page-level Tab without focusing forward_dest via any locator.
    session =
      session
      |> tab_from_account_to_room_button(forward_start)
      |> scroll_room_button_under_banner(forward_start, forward_dest)
      |> page_press("Tab")
      |> assert_focused_room_button_clears_banner(forward_dest, "Tab")

    # Reverse Shift+Tab: advance via real Tab to reverse_start, scroll so reverse_dest
    # sits completely beneath #flash-error inside the viewport, then press real
    # page-level Shift+Tab.
    session
    |> advance_tabs_to_room_button(reverse_start)
    |> scroll_room_button_under_banner(reverse_start, reverse_dest)
    |> page_press("Shift+Tab")
    |> assert_focused_room_button_clears_banner(reverse_dest, "Shift+Tab")
  end

  defp tab_from_account_to_room_button(session, target_index) do
    session
    |> click(~s|summary[aria-label="Conta"]|)
    |> assert_has("header details[open]")
    |> click(~s|summary[aria-label="Conta"]|)
    |> refute_has("header details[open]")
    |> advance_tabs_to_room_button(target_index)
  end

  defp advance_tabs_to_room_button(session, target_index, remaining \\ 20)

  defp advance_tabs_to_room_button(_session, target_index, 0) do
    flunk("did not reach room button index #{target_index} via native Tab navigation")
  end

  defp advance_tabs_to_room_button(session, target_index, remaining) do
    reached? = :ets.new(:tab_reached, [:set, :private])

    try do
      session =
        evaluate(
          session,
          """
          () => {
            const buttons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
            return document.activeElement === buttons[#{target_index}];
          }
          """,
          [is_function: true],
          fn matched -> :ets.insert(reached?, {:matched, matched}) end
        )

      case :ets.lookup(reached?, :matched) do
        [{:matched, true}] ->
          session

        _ ->
          session
          |> page_press("Tab")
          |> advance_tabs_to_room_button(target_index, remaining - 1)
      end
    after
      :ets.delete(reached?)
    end
  end

  defp scroll_room_button_under_banner(session, active_index, dest_index) do
    evaluate(
      session,
      """
      () => {
        const header = document.querySelector("header");
        const flashError = document.querySelector("#flash-error");
        const buttons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
        const activeBtn = buttons[#{active_index}];
        const destBtn = buttons[#{dest_index}];

        const headerRect = header.getBoundingClientRect();
        const bannerHeight = flashError.getBoundingClientRect().height;
        const destDocTop = destBtn.getBoundingClientRect().top + window.scrollY;
        const destHeight = destBtn.getBoundingClientRect().height;
        const desiredTop = headerRect.bottom + Math.max(4, (bannerHeight - destHeight) / 2);

        window.scrollTo({ top: Math.round(destDocTop - desiredTop), behavior: "instant" });

        const bannerRect = flashError.getBoundingClientRect();
        const destRect = destBtn.getBoundingClientRect();
        const hitBefore = document.elementFromPoint(
          (destRect.left + destRect.right) / 2,
          (destRect.top + destRect.bottom) / 2
        );

        window.__forkaFocusExpectation = {
          destLabel: destBtn.getAttribute("aria-label"),
          scrollBefore: Math.round(window.scrollY)
        };

        return {
          activeMatchesStart: document.activeElement === activeBtn,
          destNotFocused: document.activeElement !== destBtn,
          destInViewport: destRect.top >= 0 && destRect.bottom <= window.innerHeight,
          destFullyBeneathBanner:
            destRect.top >= bannerRect.top - 1 && destRect.bottom <= bannerRect.bottom + 1,
          destCoveredByBanner: Boolean(hitBefore && flashError.contains(hitBefore)),
          scrolledY: window.scrollY
        };
      }
      """,
      [is_function: true],
      fn pre ->
        assert pre["activeMatchesStart"],
               "expected starting button to hold focus before key press, got: #{inspect(pre)}"

        assert pre["destNotFocused"],
               "expected destination button not to be focused before key press, got: #{inspect(pre)}"

        assert pre["destInViewport"] and pre["destFullyBeneathBanner"],
               "expected destination button inside viewport beneath banner before key press, got: #{inspect(pre)}"

        assert pre["destCoveredByBanner"],
               "expected banner to cover destination button before key press, got: #{inspect(pre)}"
      end
    )
  end

  defp assert_focused_room_button_clears_banner(session, expected_index, key_label) do
    evaluate(
      session,
      """
      () => new Promise((resolve) => {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            const header = document.querySelector("header");
            const flashError = document.querySelector("#flash-error");
            const buttons = Array.from(document.querySelectorAll('#rooms-list button[phx-click="join_room"]'));
            const expectedBtn = buttons[#{expected_index}];
            const active = document.activeElement;

            const headerRect = header.getBoundingClientRect();
            const bannerRect = flashError.getBoundingClientRect();
            const activeRect = active.getBoundingClientRect();
            const activeStyle = getComputedStyle(active);
            const outlineWidth = activeStyle.outlineStyle === "none" ? 0 : parseFloat(activeStyle.outlineWidth) || 0;
            const outlineOffset = outlineWidth > 0 ? Math.max(0, parseFloat(activeStyle.outlineOffset) || 0) : 0;
            const ringOutset = Math.max(4, Math.ceil(outlineWidth + outlineOffset));
            const centerHit = document.elementFromPoint(
              (activeRect.left + activeRect.right) / 2,
              (activeRect.top + activeRect.bottom) / 2
            );

            resolve({
              expectedLabel: window.__forkaFocusExpectation.destLabel,
              actualLabel: active.getAttribute("aria-label"),
              activeMatchesExpected: active === expectedBtn,
              focusVisible: active.matches(":focus-visible"),
              bannerBelowHeader:
                bannerRect.height > 0 && Math.abs(bannerRect.top - headerRect.bottom) <= 1,
              clearsBannerWithRing: activeRect.top >= bannerRect.bottom + ringOutset,
              fitsInViewport: activeRect.bottom <= window.innerHeight,
              minimalScroll: activeRect.top <= bannerRect.bottom + ringOutset + 16,
              centerHitOnControl: Boolean(centerHit && active.contains(centerHit)),
              scrollBefore: window.__forkaFocusExpectation.scrollBefore,
              scrollAfter: Math.round(window.scrollY),
              bannerBottom: Math.round(bannerRect.bottom),
              activeTop: Math.round(activeRect.top),
              ringOutset
            });
          });
        });
      })
      """,
      [is_function: true],
      fn probe ->
        assert probe["activeMatchesExpected"],
               "expected #{key_label} to focus #{inspect(probe["expectedLabel"])}, got: #{inspect(probe)}"

        assert probe["focusVisible"],
               "expected #{key_label} focus target to match :focus-visible, got: #{inspect(probe)}"

        assert probe["bannerBelowHeader"],
               "expected #flash-error to stay visible directly below header after #{key_label}, got: #{inspect(probe)}"

        assert probe["clearsBannerWithRing"],
               "expected focused control and focus ring below banner after #{key_label}, got: #{inspect(probe)}"

        assert probe["fitsInViewport"],
               "expected focused control within viewport after #{key_label}, got: #{inspect(probe)}"

        assert probe["minimalScroll"],
               "expected minimal instant scroll after #{key_label}, got: #{inspect(probe)}"

        assert probe["centerHitOnControl"],
               "expected center hit-test after #{key_label} to land on focused control, got: #{inspect(probe)}"
      end
    )
  end

  defp page_press(session, "Tab") do
    send_page_key(session, :keyboard_down, "Tab")
    send_page_key(session, :keyboard_up, "Tab")
    session
  end

  defp page_press(session, "Shift+Tab") do
    send_page_key(session, :keyboard_down, "Shift")
    send_page_key(session, :keyboard_down, "Tab")
    send_page_key(session, :keyboard_up, "Tab")
    send_page_key(session, :keyboard_up, "Shift")
    session
  end

  defp send_page_key(session, method, key) do
    timeout = Config.global(:timeout)

    resp =
      Connection.send(
        Supervisor.connection_name(),
        %{guid: session.page_id, method: method, params: %{key: key}},
        timeout
      )

    refute Map.has_key?(resp, :error),
           "Playwright #{method}(#{inspect(key)}) failed: #{inspect(resp)}"
  end
end
