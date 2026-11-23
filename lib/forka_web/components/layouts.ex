defmodule ForkaWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use ForkaWeb, :controller` and
  `use ForkaWeb, :live_view`.
  """
  use ForkaWeb, :html

  embed_templates "layouts/*"

  @doc "Shows the checkout name and port when running from a linked dev worktree."
  def worktree_badge(assigns) do
    assigns = assign(assigns, :worktree, Application.get_env(:forka, :worktree))

    ~H"""
    <div
      :if={@worktree}
      id="worktree-badge"
      class="fixed bottom-3 left-3 z-50 flex items-center gap-2 rounded-full border border-line bg-surface/90 px-3 py-1 font-mono text-xs text-ink opacity-75 shadow-1 backdrop-blur transition-opacity hover:opacity-100"
      title="Running from this git worktree"
    >
      <.icon name="hero-code-bracket-square-micro" class="size-3.5" />
      <span class="font-semibold">{@worktree.name}</span>
      <span class="text-ink-subtle">:{@worktree.port}</span>
    </div>
    """
  end

  @doc "Renders the Forka brand logo with rope-arc emblem and Fredoka wordmark."
  attr :class, :string, default: nil

  def forka_logo(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-2", @class]}>
      <svg
        viewBox="0 0 36 28"
        class="h-7 w-9 shrink-0"
        fill="none"
        aria-hidden="true"
      >
        <path
          d="M 4 8 Q 18 24 32 8"
          class="stroke-rope-edge"
          stroke-width="6"
          stroke-linecap="round"
        />
        <path
          d="M 4 8 Q 18 24 32 8"
          class="stroke-rope"
          stroke-width="4"
          stroke-linecap="round"
          stroke-dasharray="4 3"
        />
        <circle cx="4" cy="8" r="3" class="fill-brand stroke-rope-edge" stroke-width="1.5" />
        <circle cx="32" cy="8" r="3" class="fill-brand stroke-rope-edge" stroke-width="1.5" />
      </svg>
      <span class="font-display text-2xl font-bold tracking-tight text-ink">Forka</span>
    </span>
    """
  end

  @doc "Renders the compact 3-state theme toggle button (System -> Light -> Dark)."
  attr :class, :string, default: nil

  def theme_toggle(assigns) do
    ~H"""
    <button
      type="button"
      data-theme-toggle
      aria-label="Tema: sistema. Trocar tema"
      class={[
        "inline-flex size-11 items-center justify-center rounded-md text-ink-muted transition-colors",
        "hover:bg-sunken hover:text-ink",
        @class
      ]}
    >
      <span data-theme-icon="system">
        <.icon name="hero-computer-desktop" class="size-5" />
      </span>
      <span data-theme-icon="light" class="hidden">
        <.icon name="hero-sun" class="size-5" />
      </span>
      <span data-theme-icon="dark" class="hidden">
        <.icon name="hero-moon" class="size-5" />
      </span>
    </button>
    """
  end

  @doc "Renders the player top navigation bar."
  attr :current_player, :any, default: nil
  attr :current_path, :string, default: nil
  slot :nav

  def player_header(assigns) do
    ~H"""
    <header class="sticky top-0 z-30 h-16 border-b border-line bg-surface px-4 sm:px-6">
      <div class="mx-auto flex h-full max-w-5xl items-center justify-between gap-4">
        <div class="flex items-center gap-6">
          <.link navigate={~p"/"} class="inline-flex items-center rounded-md py-1">
            <.forka_logo />
          </.link>

          <nav
            :if={@nav != []}
            aria-label="Navegação principal"
            class="hidden md:flex items-center gap-4"
          >
            {render_slot(@nav)}
          </nav>

          <nav
            :if={@nav == []}
            aria-label="Navegação principal"
            class="hidden md:flex items-center gap-4"
          >
            <.link
              navigate={~p"/"}
              aria-current={if(@current_path == "/", do: "page")}
              class={[
                "inline-flex min-h-11 items-center border-b-2 px-1 text-sm font-bold transition-colors",
                if(@current_path == "/",
                  do: "border-brand text-ink",
                  else: "border-transparent text-ink-muted hover:text-ink"
                )
              ]}
            >
              Salas
            </.link>
          </nav>
        </div>

        <div class="flex items-center gap-2">
          <.theme_toggle />

          <%= if @current_player do %>
            <details class="relative">
              <summary
                aria-label="Conta"
                class="flex size-11 cursor-pointer list-none items-center justify-center rounded-full hover:bg-sunken"
              >
                <.avatar initial={String.first(@current_player.email)} player_index={1} size="sm" />
              </summary>
              <div class="absolute right-0 z-40 mt-2 w-60 rounded-lg bg-surface p-2 shadow-3 ring-1 ring-line">
                <p class="truncate px-3 py-2 text-xs font-extrabold text-ink-subtle">
                  {@current_player.email}
                </p>
                <.link
                  navigate={~p"/players/settings"}
                  class="flex min-h-11 items-center rounded-md px-3 text-sm font-semibold text-ink hover:bg-sunken"
                >
                  Minha conta
                </.link>
                <.link
                  href={~p"/players/log_out"}
                  method="delete"
                  class="flex min-h-11 items-center rounded-md px-3 text-sm font-semibold text-danger-ink hover:bg-danger-soft"
                >
                  Sair
                </.link>
              </div>
            </details>
          <% else %>
            <.link
              navigate={~p"/players/register"}
              class="inline-flex min-h-11 items-center rounded-md px-3 text-sm font-bold text-ink-muted hover:bg-sunken hover:text-ink"
            >
              Criar conta
            </.link>
            <.link
              navigate={~p"/players/log_in"}
              class="inline-flex min-h-11 items-center rounded-md bg-brand px-4 font-display text-sm font-bold text-on-brand shadow-lip-brand ring-1 ring-inset ring-brand-lip transition active:translate-y-1 active:shadow-none hover:bg-brand-strong"
            >
              Entrar
            </.link>
          <% end %>
        </div>
      </div>
    </header>
    """
  end

  @doc "Renders a subpage header with a back icon button, Fredoka h1, and optional actions."
  attr :title, :string, required: true
  attr :back_to, :any, required: true
  attr :back_label, :string, default: "Voltar"
  slot :actions

  def subpage_header(assigns) do
    ~H"""
    <div class="mb-6 flex items-center justify-between gap-4">
      <div class="flex min-w-0 items-center gap-3">
        <.icon_button icon="hero-arrow-left" aria_label={@back_label} navigate={@back_to} />
        <h1 class="truncate font-display text-2xl font-bold text-ink sm:text-3xl">
          {@title}
        </h1>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
