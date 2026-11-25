defmodule ForkaWeb.PlayerConfirmationLive do
  use ForkaWeb, :live_view

  alias Forka.Players

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.card id="confirmation-card" padding="lg" bordered>
        <.header class="text-center">
          Confirmar conta
          <:subtitle>Clique no botão abaixo para confirmar seu endereço de e-mail.</:subtitle>
        </.header>

        <.simple_form for={@form} id="confirmation_form" phx-submit="confirm_account">
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <:actions>
            <.button phx-disable-with="Confirmando..." full>Confirmar minha conta</.button>
          </:actions>
        </.simple_form>

        <p class="mt-6 text-center text-sm text-ink-muted">
          <.link
            navigate={~p"/players/register?#{ForkaWeb.PlayerAuth.return_to_query(@return_to)}"}
            class="font-semibold text-brand-ink hover:underline"
          >
            Criar conta
          </.link>
          <span aria-hidden="true" class="mx-2 text-ink-subtle">·</span>
          <.link
            navigate={~p"/players/log_in?#{ForkaWeb.PlayerAuth.return_to_query(@return_to)}"}
            class="font-semibold text-brand-ink hover:underline"
          >
            Entrar
          </.link>
        </p>
      </.card>
    </div>
    """
  end

  def mount(%{"token" => token} = params, _session, socket) do
    form = to_form(%{"token" => token}, as: "player")

    {:ok,
     socket
     |> assign(:page_title, "Confirmar conta")
     |> assign(:return_to, ForkaWeb.PlayerAuth.safe_return_to(params["return_to"]))
     |> assign(:form, form), temporary_assigns: [form: nil]}
  end

  # Do not log in the player after confirmation to avoid a
  # leaked token giving the player access to the account.
  def handle_event("confirm_account", %{"player" => %{"token" => token}}, socket) do
    redirect_to = socket.assigns.return_to || ~p"/"

    case Players.confirm_player(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Conta confirmada com sucesso!")
         |> redirect(to: redirect_to)}

      :error ->
        # If there is a current player and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the player themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_player: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: redirect_to)}

          %{} ->
            {:noreply,
             socket
             |> put_flash(:error, "O link de confirmação é inválido ou expirou.")
             |> redirect(to: redirect_to)}
        end
    end
  end
end
