defmodule ForkaWeb.PlayerRegistrationLive do
  use ForkaWeb, :live_view

  alias Forka.Players
  alias Forka.Players.Player

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.card id="registration-card" padding="lg" bordered>
        <.header class="text-center">
          Criar conta
          <:subtitle>
            Já tem uma conta?
            <.link
              navigate={~p"/players/log_in"}
              class="font-semibold text-brand-ink hover:underline"
            >
              Entrar
            </.link>
          </:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          action={~p"/players/log_in?_action=registered"}
          method="post"
        >
          <.alert :if={@check_errors} tone="danger" role="alert">
            Revise os campos abaixo para continuar.
          </.alert>

          <.input
            field={@form[:email]}
            type="email"
            label="E-mail"
            autocomplete="email"
            required
          />
          <.input
            field={@form[:username]}
            type="text"
            label="Nome de usuário"
            hint="De 3 a 20 caracteres: letras, números e underline (_)."
            autocomplete="username"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            hint="Mínimo de 12 caracteres."
            autocomplete="new-password"
            required
          />

          <:actions>
            <.button phx-disable-with="Criando conta..." full>Criar conta</.button>
          </:actions>
        </.simple_form>
      </.card>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Players.change_player_registration(%Player{})

    socket =
      socket
      |> assign(page_title: "Criar conta", trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"player" => player_params}, socket) do
    case Players.register_player(player_params) do
      {:ok, player} ->
        {:ok, _} =
          Players.deliver_player_confirmation_instructions(
            player,
            &url(~p"/players/confirm/#{&1}")
          )

        changeset = Players.change_player_registration(player)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"player" => player_params}, socket) do
    changeset = Players.change_player_registration(%Player{}, player_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "player")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
