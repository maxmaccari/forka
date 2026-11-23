defmodule ForkaWeb.PlayerConfirmationInstructionsLive do
  use ForkaWeb, :live_view

  alias Forka.Players

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.card id="resend-confirmation-card" padding="lg" bordered>
        <.header class="text-center">
          Não recebeu o e-mail de confirmação?
          <:subtitle>Enviaremos um novo link de confirmação para sua caixa de entrada.</:subtitle>
        </.header>

        <.simple_form for={@form} id="resend_confirmation_form" phx-submit="send_instructions">
          <.input
            field={@form[:email]}
            type="email"
            label="E-mail"
            autocomplete="email"
            required
          />
          <:actions>
            <.button phx-disable-with="Enviando..." full>
              Reenviar instruções de confirmação
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
     |> assign(:page_title, "Reenviar confirmação")
     |> assign(:form, to_form(%{}, as: "player"))}
  end

  def handle_event("send_instructions", %{"player" => %{"email" => email}}, socket) do
    if player = Players.get_player_by_email(email) do
      Players.deliver_player_confirmation_instructions(
        player,
        &url(~p"/players/confirm/#{&1}")
      )
    end

    info =
      "Se este e-mail estiver cadastrado e ainda não confirmado, você receberá as instruções em instantes."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
