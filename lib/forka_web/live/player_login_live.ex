defmodule ForkaWeb.PlayerLoginLive do
  use ForkaWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <.card id="login-card" padding="lg" bordered>
        <.header class="text-center">
          Entrar na sua conta
          <:subtitle>
            Ainda não tem conta?
            <.link
              navigate={~p"/players/register?#{ForkaWeb.PlayerAuth.return_to_query(@return_to)}"}
              class="font-semibold text-brand-ink hover:underline"
            >
              Criar conta
            </.link>
          </:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="login_form"
          action={~p"/players/log_in?#{ForkaWeb.PlayerAuth.return_to_query(@return_to)}"}
          data-prevent-double-submit
          phx-update="ignore"
        >
          <.input
            field={@form[:email_or_username]}
            type="text"
            label="E-mail ou nome de usuário"
            autocomplete="username"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            autocomplete="current-password"
            required
          />

          <:actions>
            <.input field={@form[:remember_me]} type="checkbox" label="Manter sessão conectada" />
            <.link
              navigate={~p"/players/reset_password"}
              class="text-sm font-semibold text-brand-ink hover:underline"
            >
              Esqueceu a senha?
            </.link>
          </:actions>
          <:actions>
            <.button phx-disable-with="Entrando..." full>
              Entrar
            </.button>
          </:actions>
        </.simple_form>
      </.card>
    </div>
    """
  end

  def mount(params, _session, socket) do
    email_or_username = Phoenix.Flash.get(socket.assigns.flash, :email_or_username)
    form = to_form(%{"email_or_username" => email_or_username}, as: "player")

    {:ok,
     socket
     |> assign(:page_title, "Entrar")
     |> assign(:return_to, ForkaWeb.PlayerAuth.safe_return_to(params["return_to"]))
     |> assign(:form, form), temporary_assigns: [form: nil]}
  end
end
