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
      class="fixed bottom-3 left-3 z-50 flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white/90 px-3 py-1 font-mono text-xs text-zinc-900 opacity-70 shadow-sm backdrop-blur transition-opacity hover:opacity-100"
      title="Running from this git worktree"
    >
      <.icon name="hero-code-bracket-square-micro" class="size-3.5" />
      <span class="font-semibold">{@worktree.name}</span>
      <span class="opacity-60">:{@worktree.port}</span>
    </div>
    """
  end
end
