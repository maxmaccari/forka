defmodule ForkaWeb.AdminLoginLive do
  use ForkaWeb, :live_view

  import ForkaWeb.AdminComponents

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.admin_header class="text-center">
        Log in to backoffice
      </.admin_header>

      <.admin_simple_form for={@form} id="login_form" action={~p"/admin/log_in"} phx-update="ignore">
        <.admin_input field={@form[:email]} type="email" label="Email" required />
        <.admin_input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.admin_input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
        </:actions>
        <:actions>
          <.admin_button phx-disable-with="Logging in..." class="w-full btn-outline btn-primary">
            Log in <span aria-hidden="true">→</span>
          </.admin_button>
        </:actions>
      </.admin_simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "admin")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
