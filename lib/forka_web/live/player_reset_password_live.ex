defmodule ForkaWeb.PlayerResetPasswordLive do
  use ForkaWeb, :live_view

  alias Forka.Players

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.card id="reset-password-card" padding="lg" bordered>
        <.header class="text-center">
          Redefinir senha
          <:subtitle>Escolha uma nova senha para sua conta.</:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="reset_password_form"
          phx-submit="reset_password"
          phx-change="validate"
        >
          <:alert>
            <.alert :if={@check_errors} tone="danger" role="alert" class="w-full">
              Revise os campos abaixo para continuar.
            </.alert>
          </:alert>

          <.input
            field={@form[:password]}
            type="password"
            label="Nova senha"
            hint="Mínimo de 12 caracteres."
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirmar nova senha"
            autocomplete="new-password"
            required
          />
          <:actions>
            <.button phx-disable-with="Salvando..." full>Redefinir senha</.button>
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

  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Redefinir senha", check_errors: false)
      |> assign_player_and_token(params)

    form_source =
      case socket.assigns do
        %{player: player} ->
          Players.change_player_password(player)

        _ ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the player after reset password to avoid a
  # leaked token giving the player access to the account.
  def handle_event("reset_password", %{"player" => player_params}, socket) do
    case Players.reset_player_password(socket.assigns.player, player_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Senha redefinida com sucesso!")
         |> redirect(to: ~p"/players/log_in")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:check_errors, true)
         |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"player" => player_params}, socket) do
    changeset = Players.change_player_password(socket.assigns.player, player_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_player_and_token(socket, %{"token" => token}) do
    if player = Players.get_player_by_reset_password_token(token) do
      assign(socket, player: player, token: token)
    else
      socket
      |> put_flash(:error, "O link para redefinir a senha é inválido ou expirou.")
      |> redirect(to: ~p"/players/reset_password")
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "player")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "player"))
  end
end
