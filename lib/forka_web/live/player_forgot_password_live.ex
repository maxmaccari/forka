defmodule ForkaWeb.PlayerForgotPasswordLive do
  use ForkaWeb, :live_view

  alias Forka.Players

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.card id="forgot-password-card" padding="lg" bordered>
        <.header class="text-center">
          Esqueceu a senha?
          <:subtitle>Enviaremos um link para você criar uma nova senha.</:subtitle>
        </.header>

        <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
          <.input
            field={@form[:email]}
            type="email"
            label="E-mail"
            autocomplete="email"
            required
          />
          <:actions>
            <.button phx-disable-with="Enviando..." full>
              Enviar instruções
            </.button>
          </:actions>
        </.simple_form>

        <p class="mt-6 text-center text-sm text-ink-muted">
          <.link
            navigate={~p"/players/register"}
            class="font-semibold text-brand-ink hover:underline"
          >
            Criar conta
          </.link>
          <span aria-hidden="true" class="mx-2 text-ink-subtle">·</span>
          <.link
            navigate={~p"/players/log_in"}
            class="font-semibold text-brand-ink hover:underline"
          >
            Entrar
          </.link>
        </p>
      </.card>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Recuperar senha")
     |> assign(:form, to_form(%{}, as: "player"))}
  end

  def handle_event("send_email", %{"player" => %{"email" => email}}, socket) do
    if player = Players.get_player_by_email(email) do
      Players.deliver_player_reset_password_instructions(
        player,
        &url(~p"/players/reset_password/#{&1}")
      )
    end

    info =
      "Se este e-mail estiver cadastrado, você receberá as instruções para redefinir sua senha em instantes."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
