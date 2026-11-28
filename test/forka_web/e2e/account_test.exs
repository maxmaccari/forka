defmodule ForkaWeb.E2E.AccountTest do
  # Runs in Chromium (`mix test.e2e`). Uses `async: false` because
  # `Swoosh.TestAssertions.set_swoosh_global/1` routes emails from LiveView
  # processes to this test process and requires non-async execution.
  use ForkaWeb.E2ECase, async: false

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Forka.Players
  alias Forka.Players.PlayerToken
  alias Forka.Repo
  alias PhoenixTest.Playwright.Config
  alias PlaywrightEx.{Frame, Page, Route}
  alias Swoosh.Email

  setup :set_swoosh_global

  test "AC-01: a new player registers, lands signed in, and confirms the account from email", %{
    conn: conn
  } do
    email = "nova_jogadora@example.com"
    username = "nova_jogadora"
    password = "SenhaSegura123!"

    conn =
      conn
      |> visit(~p"/players/register")
      |> assert_has("[data-phx-main].phx-connected")
      |> fill_in("E-mail", with: email)
      |> fill_in("Nome de usuário", with: username)
      |> fill_in("Senha", with: password)
      |> click_button("Criar conta")
      |> assert_path(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#rooms-live-status", text: "Ao vivo")
      |> assert_has("#flash-info", text: "Conta criada com sucesso!")
      |> assert_has(~s|summary[aria-label="Conta"]|)

    confirm_path = receive_email_path!(email, "Confirmation instructions")

    conn
    |> visit(confirm_path)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Confirmar conta")
    |> click_button("Confirmar minha conta")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
    |> assert_has("#flash-info", text: "Conta confirmada com sucesso!")
    |> assert_has(~s|summary[aria-label="Conta"]|)

    player = Players.get_player_by_email(email)
    assert player.username == username
    refute is_nil(player.confirmed_at)
  end

  test "AC-02: a player signs in, signs out, and returns to the public room directory", %{
    conn: conn
  } do
    player = insert(:player, username: "lia")

    conn
    |> visit(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> fill_in("E-mail ou nome de usuário", with: player.email)
    |> fill_in("Senha", with: "Password1!456")
    |> click_button("Entrar")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
    |> assert_has("#flash-info", text: "Bem-vindo de volta!")
    |> assert_has(~s|summary[aria-label="Conta"]|)
    # Dismiss the flash toast because fixed top-3 right-3 overlaps the top-right Conta button.
    |> click("#flash-info")
    |> refute_has("#flash-info")
    |> click(~s|summary[aria-label="Conta"]|)
    |> click_link("Sair")
    |> assert_has("#flash-info", text: "Você saiu da conta.")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
    |> refute_has(~s|summary[aria-label="Conta"]|)
    |> assert_has("header a", text: "Entrar")
    |> assert_has("header a", text: "Criar conta")
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}, is_mobile: true]
  test "AC-06: a player signs in and signs out on the mobile viewport", %{conn: conn} do
    player = insert(:player, username: "bruno")

    conn
    |> visit(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> evaluate("window.innerWidth", &assert(&1 == 390))
    |> fill_in("E-mail ou nome de usuário", with: player.email)
    |> fill_in("Senha", with: "Password1!456")
    |> click_button("Entrar")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
    |> assert_has("#flash-info", text: "Bem-vindo de volta!")
    |> assert_has("#create-room-mobile", text: "Criar sala")
    |> assert_has(~s|summary[aria-label="Conta"]|)
    # Dismiss the flash toast because fixed top-3 right-3 overlaps the top-right Conta button.
    |> click("#flash-info")
    |> refute_has("#flash-info")
    |> click(~s|summary[aria-label="Conta"]|)
    |> click_link("Sair")
    |> assert_has("#flash-info", text: "Você saiu da conta.")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> refute_has(~s|summary[aria-label="Conta"]|)
    |> assert_has("header a", text: "Entrar")
  end

  test "AC-03: wrong password and invalid registration fields show pt-BR error messages", %{
    conn: conn
  } do
    player = insert(:player, email: "existente@example.com")

    conn
    |> visit(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> fill_in("E-mail ou nome de usuário", with: player.email)
    |> fill_in("Senha", with: "SenhaErrada123!")
    |> click_button("Entrar")
    |> assert_has("#flash-error", text: "E-mail, usuário ou senha inválidos.")
    |> assert_path(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has(~s|input[name="player[email_or_username]"]|, value: player.email)
    |> refute_has(~s|summary[aria-label="Conta"]|)
    |> visit(~p"/players/register")
    |> assert_has("[data-phx-main].phx-connected")
    |> fill_in("E-mail", with: player.email)
    |> fill_in("Nome de usuário", with: "bad user!")
    |> fill_in("Senha", with: "curta123")
    |> click_button("Criar conta")
    |> assert_has(
      ~s|#registration_form [role="alert"]|,
      text: "Revise os campos abaixo para continuar."
    )
    |> assert_path(~p"/players/register")
    |> assert_has("#player_email-feedback", text: "já está em uso")
    |> assert_has(
      "#player_username-feedback",
      text: "use apenas letras, números e underline (_)"
    )
    |> assert_has("#player_password-feedback", text: "deve ter no mínimo 12 caracteres")
  end

  test "AC-04: a player requests a password reset, follows the email link, and signs in with the new password",
       %{conn: conn} do
    player = insert(:player, email: "recuperar@example.com")
    new_password = "NovaSenhaForte123!"

    conn =
      conn
      |> visit(~p"/players/log_in")
      |> assert_has("[data-phx-main].phx-connected")
      |> click_link("Esqueceu a senha?")
      |> assert_path(~p"/players/reset_password")
      |> assert_has("[data-phx-main].phx-connected")
      |> fill_in("E-mail", with: player.email)
      |> click_button("Enviar instruções")
      |> assert_path(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has(
        "#flash-info",
        text:
          "Se este e-mail estiver cadastrado, você receberá as instruções para redefinir sua senha em instantes."
      )

    reset_path = receive_email_path!(player.email, "Reset password instructions")

    conn
    |> visit(reset_path)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Redefinir senha")
    |> fill_in("Nova senha", with: new_password)
    |> fill_in("Confirmar nova senha", with: new_password)
    |> click_button("Redefinir senha")
    |> assert_path(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-info", text: "Senha redefinida com sucesso!")
    |> fill_in("E-mail ou nome de usuário", with: player.email)
    |> fill_in("Senha", with: new_password)
    |> click_button("Entrar")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#rooms-live-status", text: "Ao vivo")
    |> assert_has("#flash-info", text: "Bem-vindo de volta!")
    |> assert_has(~s|summary[aria-label="Conta"]|)
  end

  test "EDGE-01: expired and already-used reset links show a clear pt-BR error and a way to request a new link",
       %{conn: conn} do
    player = insert(:player)
    expired_token = create_reset_token!(player)
    backdate_reset_tokens!(player, 2)

    conn =
      conn
      |> visit(~p"/players/reset_password/#{expired_token}")
      |> assert_path(~p"/players/reset_password")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#flash-error", text: "O link para redefinir a senha é inválido ou expirou.")
      |> assert_has("h1", text: "Esqueceu a senha?")
      |> assert_has("#reset_password_form button", text: "Enviar instruções")

    used_token = create_reset_token!(player)

    {:ok, _player} =
      Players.reset_player_password(used_token, %{
        password: "NovaSenhaUsada123!",
        password_confirmation: "NovaSenhaUsada123!"
      })

    conn
    |> visit(~p"/players/reset_password/#{used_token}")
    |> assert_path(~p"/players/reset_password")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-error", text: "O link para redefinir a senha é inválido ou expirou.")
    |> assert_has("#reset_password_form button", text: "Enviar instruções")
  end

  test "MAX-57: submitting an open reset form after its link expires or is used in another tab keeps the password and lets the player request a new link",
       %{conn: conn} = context do
    player = insert(:player, email: "open-reset@example.com")
    expired_token = create_reset_token!(player)

    conn =
      conn
      |> visit(~p"/players/reset_password/#{expired_token}")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Redefinir senha")
      |> fill_in("Nova senha", with: "SenhaExpirada123!")
      |> fill_in("Confirmar nova senha", with: "SenhaExpirada123!")

    backdate_reset_tokens!(player, 2)

    conn =
      conn
      |> click_button("Redefinir senha")
      |> assert_path(~p"/players/reset_password")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#flash-error", text: "O link para redefinir a senha é inválido ou expirou.")
      |> assert_has("h1", text: "Esqueceu a senha?")
      |> assert_has("#reset_password_form button", text: "Enviar instruções")

    assert Players.get_player_by_email_and_password(player.email, "Password1!456")
    refute Players.get_player_by_email_and_password(player.email, "SenhaExpirada123!")

    shared_token = create_reset_token!(player)

    conn =
      conn
      |> visit(~p"/players/reset_password/#{shared_token}")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("h1", text: "Redefinir senha")

    context
    |> second_session()
    |> visit(~p"/players/reset_password/#{shared_token}")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Redefinir senha")
    |> fill_in("Nova senha", with: "NovaSenhaAbaDois123!")
    |> fill_in("Confirmar nova senha", with: "NovaSenhaAbaDois123!")
    |> click_button("Redefinir senha")
    |> assert_path(~p"/players/log_in")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-info", text: "Senha redefinida com sucesso!")

    conn
    |> fill_in("Nova senha", with: "NovaSenhaAbaUm123!")
    |> fill_in("Confirmar nova senha", with: "NovaSenhaAbaUm123!")
    |> click_button("Redefinir senha")
    |> assert_path(~p"/players/reset_password")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#flash-error", text: "O link para redefinir a senha é inválido ou expirou.")
    |> assert_has("h1", text: "Esqueceu a senha?")
    |> fill_in("E-mail", with: player.email)
    |> click_button("Enviar instruções")
    |> assert_path(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has(
      "#flash-info",
      text:
        "Se este e-mail estiver cadastrado, você receberá as instruções para redefinir sua senha em instantes."
    )

    assert Players.get_player_by_email_and_password(player.email, "NovaSenhaAbaDois123!")
    refute Players.get_player_by_email_and_password(player.email, "NovaSenhaAbaUm123!")

    new_reset_path = receive_email_path!(player.email, "Reset password instructions")
    assert String.starts_with?(new_reset_path, "/players/reset_password/")
    refute new_reset_path == ~p"/players/reset_password/#{shared_token}"
  end

  test "AC-05: a player changes their password on the account settings screen and sees the success message",
       %{conn: conn} do
    player = insert(:player)
    new_password = "NovaSenhaConta123!"

    conn
    |> log_in(player)
    # Dismiss the flash toast because fixed top-3 right-3 overlaps the top-right Conta button.
    |> click("#flash-info")
    |> refute_has("#flash-info")
    |> click(~s|summary[aria-label="Conta"]|)
    |> click_link("Minha conta")
    |> assert_path(~p"/players/settings")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("h1", text: "Minha conta")
    |> within("#password_form", fn session ->
      session
      |> fill_in("Nova senha", with: new_password)
      |> fill_in("Confirmar nova senha", with: new_password)
      |> fill_in("Senha atual", with: "Password1!456")
      |> click_button("Alterar senha")
    end)
    |> assert_has("#flash-info", text: "Senha atualizada com sucesso!")
    |> assert_path(~p"/players/settings")
    |> assert_has("[data-phx-main].phx-connected")

    assert Players.get_player_by_email_and_password(player.email, new_password)
  end

  test "EDGE-02: double-clicking the sign-in button signs in once without an error", %{
    conn: conn
  } do
    player = insert(:player)
    timeout = Config.global(:timeout)
    test_pid = self()
    post_counter = :counters.new(1, [:atomics])

    conn =
      conn
      |> visit(~p"/players/log_in")
      |> assert_has("[data-phx-main].phx-connected")
      |> fill_in("E-mail ou nome de usuário", with: player.email)
      |> fill_in("Senha", with: "Password1!456")

    conn =
      unwrap(conn, fn %{page_id: page_id} ->
        {:ok, _} =
          Page.route(
            page_id,
            "**/players/log_in",
            fn route, request ->
              handle_login_route(route, request, post_counter, test_pid, timeout)
            end,
            timeout: timeout,
            on_error: :message
          )
      end)

    try do
      conn
      |> unwrap(fn %{page_id: page_id, frame_id: frame_id} ->
        {:ok, _} =
          Frame.evaluate(
            frame_id,
            expression: """
            () => {
              sessionStorage.setItem("__eligibleLoginSubmitCount", "0");
              document.addEventListener("submit", (event) => {
                if (event.target && event.target.id === "login_form" && !event.defaultPrevented) {
                  const count =
                    Number(sessionStorage.getItem("__eligibleLoginSubmitCount") || "0") + 1;
                  sessionStorage.setItem("__eligibleLoginSubmitCount", String(count));
                }
              });
            }
            """,
            is_function: true,
            timeout: timeout
          )

        {x, y} = login_button_center(frame_id, timeout)

        {:ok, _} = Page.mouse_move(page_id, x: x, y: y, timeout: timeout)
        {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
        {:ok, _} = Page.mouse_up(page_id, timeout: timeout)

        assert_receive {:login_post, 1, first_route_pid}, timeout

        {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
        {:ok, _} = Page.mouse_up(page_id, timeout: timeout)

        send(first_route_pid, :release)
      end)
      |> assert_path(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#rooms-live-status", text: "Ao vivo")
      |> assert_has("#flash-info", text: "Bem-vindo de volta!")
      |> refute_has("#flash-error")
      |> assert_has(~s|summary[aria-label="Conta"]|)
      |> evaluate(
        "Number(sessionStorage.getItem('__eligibleLoginSubmitCount'))",
        &assert(&1 == 1)
      )
    after
      unwrap(conn, fn %{page_id: page_id} ->
        {:ok, _} = Page.unroute_all(page_id, timeout: timeout)
      end)
    end

    assert :counters.get(post_counter, 1) == 1
    assert session_token_count(player) == 1
  end

  test "EDGE-02: stopping an in-flight sign-in keeps the button usable and retries after the window even if the wall clock moves back",
       %{conn: conn} do
    player = insert(:player)
    timeout = Config.global(:timeout)
    test_pid = self()
    post_counter = :counters.new(1, [:atomics])

    conn =
      conn
      |> visit(~p"/players/log_in")
      |> assert_has("[data-phx-main].phx-connected")
      |> fill_in("E-mail ou nome de usuário", with: player.email)
      |> fill_in("Senha", with: "Password1!456")

    conn =
      unwrap(conn, fn %{page_id: page_id} ->
        {:ok, _} =
          Page.route(
            page_id,
            "**/players/log_in",
            fn route, request ->
              handle_login_route(route, request, post_counter, test_pid, timeout)
            end,
            timeout: timeout,
            on_error: :message
          )
      end)

    try do
      conn
      |> unwrap(fn %{page_id: page_id, frame_id: frame_id} ->
        {:ok, _} =
          Frame.evaluate(
            frame_id,
            expression: """
            () => {
              window.__firstSubmitAt = null;
              document.addEventListener("submit", (event) => {
                if (
                  event.target &&
                  event.target.id === "login_form" &&
                  !event.defaultPrevented &&
                  window.__firstSubmitAt === null
                ) {
                  window.__firstSubmitAt = performance.now();
                }
              });
            }
            """,
            is_function: true,
            timeout: timeout
          )

        {x, y} = login_button_center(frame_id, timeout)

        {:ok, _} = Page.mouse_move(page_id, x: x, y: y, timeout: timeout)
        {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
        {:ok, _} = Page.mouse_up(page_id, timeout: timeout)

        assert_receive {:login_post, 1, first_route_pid}, timeout
        send(first_route_pid, :abort)
        {:ok, _} = Frame.evaluate(frame_id, expression: "window.stop()", timeout: timeout)
      end)
      |> assert_path(~p"/players/log_in")
      |> assert_has("#login_form button:not([disabled])", text: "Entrar")
      |> refute_has("#login_form button[disabled]")
      |> unwrap(fn %{frame_id: frame_id} ->
        {:ok, _} =
          Frame.evaluate(
            frame_id,
            expression: """
            () => {
              const realDateNow = Date.now.bind(Date);
              Date.now = () => realDateNow() - 3_600_000;

              const form = document.querySelector("#login_form");
              const submittedAt = window.__firstSubmitAt ?? performance.now();
              const waitForWindow = () => {
                if (performance.now() - submittedAt >= 1100) {
                  form.dataset.retryWindowElapsed = "true";
                } else {
                  requestAnimationFrame(waitForWindow);
                }
              };
              requestAnimationFrame(waitForWindow);
            }
            """,
            is_function: true,
            timeout: timeout
          )
      end)
      |> assert_has(~s|#login_form[data-retry-window-elapsed="true"]|, timeout: 3_000)
      |> assert_has("#login_form button:not([disabled])", text: "Entrar")
      |> click_button("Entrar")
      |> assert_path(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#rooms-live-status", text: "Ao vivo")
      |> assert_has("#flash-info", text: "Bem-vindo de volta!")
      |> refute_has("#flash-error")
      |> assert_has(~s|summary[aria-label="Conta"]|)
    after
      unwrap(conn, fn %{page_id: page_id} ->
        {:ok, _} = Page.unroute_all(page_id, timeout: timeout)
      end)
    end

    assert :counters.get(post_counter, 1) == 2
    assert session_token_count(player) == 1
  end

  test "EDGE-02: double-clicking sign-in before LiveView connects signs in once without an error",
       %{conn: conn} do
    player = insert(:player)
    timeout = Config.global(:timeout)
    test_pid = self()
    post_counter = :counters.new(1, [:atomics])
    app_js_counter = :counters.new(1, [:atomics])

    conn = route_pre_connect_login(conn, app_js_counter, post_counter, test_pid, timeout)

    try do
      conn =
        conn
        |> visit(~p"/players/log_in")
        |> refute_has("[data-phx-main].phx-connected")
        |> evaluate("typeof window.liveSocket", &assert(&1 == "undefined"))
        |> fill_in("E-mail ou nome de usuário", with: player.email)
        |> fill_in("Senha", with: "Password1!456")
        |> unwrap(fn %{page_id: page_id, frame_id: frame_id} ->
          track_login_submits(frame_id, timeout)
          {x, y} = login_button_center(frame_id, timeout)

          {:ok, _} = Page.mouse_move(page_id, x: x, y: y, timeout: timeout)
          {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
          {:ok, _} = Page.mouse_up(page_id, timeout: timeout)
        end)

      assert_receive {:login_post, 1, first_route_pid}, timeout

      conn
      |> unwrap(fn %{page_id: page_id} ->
        {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
        {:ok, _} = Page.mouse_up(page_id, timeout: timeout)

        send(first_route_pid, :release)
      end)
      |> assert_path(~p"/")
      |> assert_has("#flash-info", text: "Bem-vindo de volta!")
      |> refute_has("#flash-error")
      |> assert_has(~s|summary[aria-label="Conta"]|)
      |> evaluate(
        "Number(sessionStorage.getItem('__eligibleLoginSubmitCount'))",
        &assert(&1 == 1)
      )
    after
      unwrap(conn, fn %{page_id: page_id} ->
        {:ok, _} = Page.unroute_all(page_id, timeout: timeout)
      end)
    end

    assert :counters.get(app_js_counter, 1) >= 1
    assert :counters.get(post_counter, 1) == 1
    assert session_token_count(player) == 1
  end

  test "EDGE-02: repeating sign-in about 500ms apart before LiveView connects signs in once without an error",
       %{conn: conn} do
    player = insert(:player)
    timeout = Config.global(:timeout)
    test_pid = self()
    post_counter = :counters.new(1, [:atomics])
    app_js_counter = :counters.new(1, [:atomics])

    conn = route_pre_connect_login(conn, app_js_counter, post_counter, test_pid, timeout)

    try do
      conn =
        conn
        |> visit(~p"/players/log_in")
        |> refute_has("[data-phx-main].phx-connected")
        |> evaluate("typeof window.liveSocket", &assert(&1 == "undefined"))
        |> fill_in("E-mail ou nome de usuário", with: player.email)
        |> fill_in("Senha", with: "Password1!456")
        |> unwrap(fn %{page_id: page_id, frame_id: frame_id} ->
          track_login_submits(frame_id, timeout, mark_after_ms: 500)
          {x, y} = login_button_center(frame_id, timeout)

          {:ok, _} = Page.mouse_move(page_id, x: x, y: y, timeout: timeout)
          {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
          {:ok, _} = Page.mouse_up(page_id, timeout: timeout)
        end)

      assert_receive {:login_post, 1, first_route_pid}, timeout
      assert_receive {:half_window_elapsed, %{disabled: false, label: "Entrar"}}, timeout

      conn
      |> unwrap(fn %{page_id: page_id} ->
        {:ok, _} = Page.mouse_down(page_id, timeout: timeout)
        {:ok, _} = Page.mouse_up(page_id, timeout: timeout)

        send(first_route_pid, :release)
      end)
      |> assert_path(~p"/")
      |> assert_has("#flash-info", text: "Bem-vindo de volta!")
      |> refute_has("#flash-error")
      |> assert_has(~s|summary[aria-label="Conta"]|)
      |> evaluate(
        "Number(sessionStorage.getItem('__eligibleLoginSubmitCount'))",
        &assert(&1 == 1)
      )
    after
      unwrap(conn, fn %{page_id: page_id} ->
        {:ok, _} = Page.unroute_all(page_id, timeout: timeout)
      end)
    end

    assert :counters.get(app_js_counter, 1) >= 1
    assert :counters.get(post_counter, 1) == 1
    assert session_token_count(player) == 1
  end

  defp route_pre_connect_login(conn, app_js_counter, post_counter, test_pid, timeout) do
    unwrap(conn, fn %{page_id: page_id} ->
      {:ok, _} =
        Page.route(
          page_id,
          "**/*",
          &handle_pre_connect_route(&1, &2, app_js_counter, post_counter, test_pid, timeout),
          timeout: timeout,
          on_error: :message
        )
    end)
  end

  defp handle_pre_connect_route(route, request, app_js_counter, post_counter, test_pid, timeout) do
    uri = URI.parse(request.url)

    cond do
      request.url =~ ~r|/assets/app[^/]*\.js| ->
        :counters.add(app_js_counter, 1, 1)
        Route.abort(route, error_code: "aborted")

      uri.path == "/__half_window_elapsed" ->
        query = URI.decode_query(uri.query || "")

        send(test_pid, {
          :half_window_elapsed,
          %{disabled: query["disabled"] == "true", label: query["label"]}
        })

        Route.fulfill(route, status: 204, body: "")

      request.method == "POST" and uri.path == "/players/log_in" ->
        handle_login_route(route, request, post_counter, test_pid, timeout)

      true ->
        Route.continue(route)
    end
  end

  defp track_login_submits(frame_id, timeout, opts \\ []) do
    mark_after_ms = Keyword.get(opts, :mark_after_ms)

    mark_after_js =
      if is_integer(mark_after_ms) do
        """
        const btn = event.target.querySelector("button");
        const submittedAt = window.__firstSubmitAt;
        const waitForHalfWindow = () => {
          if (performance.now() - submittedAt >= #{mark_after_ms}) {
            const params = new URLSearchParams({
              disabled: String(Boolean(btn && btn.disabled)),
              label: (btn && btn.textContent ? btn.textContent.trim() : "")
            });
            fetch("/__half_window_elapsed?" + params.toString());
          } else {
            requestAnimationFrame(waitForHalfWindow);
          }
        };
        requestAnimationFrame(waitForHalfWindow);
        """
      else
        ""
      end

    {:ok, _} =
      Frame.evaluate(
        frame_id,
        expression: """
        () => {
          sessionStorage.setItem("__eligibleLoginSubmitCount", "0");
          window.__firstSubmitAt = null;
          document.addEventListener("submit", (event) => {
            if (event.target && event.target.id === "login_form" && !event.defaultPrevented) {
              const count =
                Number(sessionStorage.getItem("__eligibleLoginSubmitCount") || "0") + 1;
              sessionStorage.setItem("__eligibleLoginSubmitCount", String(count));
              if (window.__firstSubmitAt === null) {
                window.__firstSubmitAt = performance.now();
                #{mark_after_js}
              }
            }
          });
        }
        """,
        is_function: true,
        timeout: timeout
      )
  end

  defp login_button_center(frame_id, timeout) do
    {:ok, %{"x" => x, "y" => y}} =
      Frame.evaluate(
        frame_id,
        expression: """
        () => {
          const btn = document.querySelector("#login_form button");
          btn.scrollIntoView({ block: "center" });
          const rect = btn.getBoundingClientRect();
          return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
        }
        """,
        is_function: true,
        timeout: timeout
      )

    {x, y}
  end

  defp handle_login_route(route, %{method: "POST"}, post_counter, test_pid, timeout) do
    :counters.add(post_counter, 1, 1)
    attempt = :counters.get(post_counter, 1)
    send(test_pid, {:login_post, attempt, self()})

    action =
      if attempt == 1 do
        receive do
          :release -> :continue
          :abort -> :abort
        after
          timeout -> :continue
        end
      else
        :continue
      end

    case action do
      :continue -> Route.continue(route)
      :abort -> Route.abort(route, error_code: "aborted")
    end
  end

  defp handle_login_route(route, _request, _post_counter, _test_pid, _timeout) do
    Route.continue(route)
  end

  defp session_token_count(player) do
    Repo.aggregate(
      from(t in PlayerToken, where: t.player_id == ^player.id and t.context == "session"),
      :count
    )
  end

  defp receive_email_path!(recipient_email, expected_subject) do
    assert_receive {:email, %Email{subject: ^expected_subject, to: to, text_body: body}}, 2_000

    assert Enum.any?(to, fn {_name, address} -> address == recipient_email end),
           "expected email to #{recipient_email}, got: #{inspect(to)}"

    [url] =
      Regex.run(~r|https?://[^\s]+|, body) ||
        flunk("expected URL in email body, got: #{inspect(body)}")

    expected_origin = URI.parse(ForkaWeb.Endpoint.url())
    uri = URI.parse(url)

    assert {uri.scheme, uri.host, uri.port} ==
             {expected_origin.scheme, expected_origin.host, expected_origin.port},
           "expected email URL origin #{ForkaWeb.Endpoint.url()}, got: #{url}"

    # Visit only path and query because the test server listens on a random port.
    if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path
  end

  defp create_reset_token!(player) do
    {:ok, %{text_body: body}} =
      Players.deliver_player_reset_password_instructions(
        player,
        &"[TOKEN]#{&1}[TOKEN]"
      )

    assert_receive {:email, %Email{subject: "Reset password instructions"}}
    [_, token | _] = String.split(body, "[TOKEN]")
    token
  end

  defp backdate_reset_tokens!(player, days_ago) do
    past = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second)

    {count, _} =
      from(t in PlayerToken,
        where: t.player_id == ^player.id and t.context == "reset_password"
      )
      |> Repo.update_all(set: [inserted_at: past])

    assert count > 0
  end
end
