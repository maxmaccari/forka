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
      Players.reset_player_password(player, %{
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
