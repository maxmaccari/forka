defmodule ForkaWeb.PlayerSettingsLive do
  use ForkaWeb, :live_view

  alias Forka.Players
  alias ForkaWeb.Layouts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <Layouts.subpage_header
        title="Minha conta"
        back_to={~p"/"}
        back_label="Voltar para o início"
      />

      <div class="space-y-6">
        <.card id="email-settings-card" padding="lg" bordered>
          <:title>E-mail</:title>
          <p class="text-sm text-ink-muted">
            Atualize o endereço de e-mail usado para entrar e recuperar sua conta.
          </p>

          <.simple_form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
            <.input
              field={@email_form[:username]}
              type="text"
              label="Nome de usuário"
              disabled
            />
            <.input
              field={@email_form[:email]}
              type="email"
              label="E-mail"
              autocomplete="email"
              required
            />
            <.input
              field={@email_form[:current_password]}
              name="current_password"
              id="current_password_for_email"
              type="password"
              label="Senha atual"
              autocomplete="current-password"
              value={@email_form_current_password}
              required
            />
            <:actions>
              <.button phx-disable-with="Salvando...">Alterar e-mail</.button>
            </:actions>
          </.simple_form>
        </.card>

        <.card id="password-settings-card" padding="lg" bordered>
          <:title>Senha</:title>
          <p class="text-sm text-ink-muted">
            Use uma senha com pelo menos 12 caracteres para manter sua conta protegida.
          </p>

          <.simple_form
            for={@password_form}
            id="password_form"
            action={~p"/players/log_in?_action=password_updated"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_player_email"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="Nova senha"
              hint="Mínimo de 12 caracteres."
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirmar nova senha"
              autocomplete="new-password"
            />
            <.input
              field={@password_form[:current_password]}
              name="current_password"
              type="password"
              label="Senha atual"
              id="current_password_for_password"
              autocomplete="current-password"
              value={@current_password}
              required
            />
            <:actions>
              <.button phx-disable-with="Salvando...">Alterar senha</.button>
            </:actions>
          </.simple_form>
        </.card>

        <.card id="session-settings-card" padding="lg" bordered>
          <:title>Sessão</:title>
          <p class="text-sm text-ink-muted">
            Encerre sua sessão atual neste dispositivo.
          </p>
          <:actions>
            <.button variant="danger-link" href={~p"/players/log_out"} method="delete">
              Sair da conta
            </.button>
          </:actions>
        </.card>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Players.update_player_email(socket.assigns.current_player, token) do
        :ok ->
          put_flash(socket, :info, "E-mail alterado com sucesso!")

        :error ->
          put_flash(socket, :error, "O link de alteração de e-mail é inválido ou expirou.")
      end

    {:ok, push_navigate(socket, to: ~p"/players/settings")}
  end

  def mount(_params, _session, socket) do
    player = socket.assigns.current_player
    email_changeset = Players.change_player_email(player)
    password_changeset = Players.change_player_password(player)

    socket =
      socket
      |> assign(:page_title, "Minha conta")
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, player.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "player" => player_params} = params

    email_form =
      socket.assigns.current_player
      |> Players.change_player_email(player_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "player" => player_params} = params
    player = socket.assigns.current_player

    case Players.apply_player_email(player, password, player_params) do
      {:ok, applied_player} ->
        Players.deliver_player_update_email_instructions(
          applied_player,
          player.email,
          &url(~p"/players/settings/confirm_email/#{&1}")
        )

        info = "Enviamos um link de confirmação para o novo e-mail."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "player" => player_params} = params

    password_form =
      socket.assigns.current_player
      |> Players.change_player_password(player_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "player" => player_params} = params
    player = socket.assigns.current_player

    case Players.update_player_password(player, password, player_params) do
      {:ok, player} ->
        password_form =
          player
          |> Players.change_player_password(player_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end
end
