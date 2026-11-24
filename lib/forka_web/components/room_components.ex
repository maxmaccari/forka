defmodule ForkaWeb.RoomComponents do
  @moduledoc """
  Domain presentation components for Forka's live room directory.

  Maps `Forka.Games.RoomListItem` read models to Forka UI primitives and semantic tokens.
  """
  use Phoenix.Component
  use ForkaWeb, :verified_routes

  import ForkaWeb.CoreComponents

  alias Forka.Games.RoomListItem

  @doc "Renders a room status pill using Forka's `<.badge>` primitive."
  attr :status, :atom,
    required: true,
    values: [:lobby, :playing, :finished, :game_over, :archived]

  attr :class, :string, default: nil

  def room_status_badge(assigns) do
    ~H"""
    <.badge tone={status_tone(@status)} class={@class}>{status_label(@status)}</.badge>
    """
  end

  defp status_tone(:lobby), do: "success"
  defp status_tone(:playing), do: "warning"
  defp status_tone(_), do: "neutral"

  defp status_label(:lobby), do: "Na sala"
  defp status_label(:playing), do: "Jogando"
  defp status_label(_), do: "Terminada"

  @doc "Renders a responsive room card for the live room directory."
  attr :id, :string, required: true
  attr :room, RoomListItem, required: true
  attr :current_player, :any, default: nil

  def room_card(assigns) do
    owner_name = assigns.room.owner_username || "Anônimo"

    assigns =
      assigns
      |> assign(:owner_name, owner_name)
      |> assign(:owner_color, owner_color_index(owner_name))
      |> assign(:joinable?, RoomListItem.joinable?(assigns.room))
      |> assign(:closed_note, closed_note(RoomListItem.availability_state(assigns.room)))
      |> assign(:lang_code, language_code(assigns.room.language))
      |> assign(:categories_text, categories_label(assigns.room.category_names))

    ~H"""
    <.card id={@id} padding="responsive" layout="inline_header" bordered>
      <:title>{@room.name}</:title>
      <:badge>
        <.room_status_badge status={@room.status} />
      </:badge>

      <div class="flex items-center gap-3">
        <.avatar name={@owner_name} player_index={@owner_color} size="xs" />
        <p class="min-w-0 flex-1 text-sm text-ink-subtle">
          de <strong class="font-bold text-ink-muted">{@owner_name}</strong>
          · {@lang_code} · <span class="tabular-nums">{@room.player_count}/{@room.max_players}</span>
          jogadores
        </p>
      </div>

      <p class="truncate text-xs font-semibold text-ink-subtle">
        {@categories_text}
      </p>

      <:actions>
        <%= if @joinable? do %>
          <%= if @current_player do %>
            <.button
              variant="secondary"
              size="sm"
              phx-click="join_room"
              phx-value-id={@room.id}
              aria-label={"Entrar na sala #{@room.name}"}
            >
              Entrar
            </.button>
          <% else %>
            <.button
              variant="secondary"
              size="sm"
              navigate={~p"/players/log_in"}
              aria-label={"Entrar na sala #{@room.name}"}
            >
              Entrar
            </.button>
          <% end %>
        <% else %>
          <span class="inline-flex min-h-11 items-center text-sm font-bold text-ink-subtle">
            {@closed_note}
          </span>
        <% end %>
      </:actions>
    </.card>
    """
  end

  @doc "Renders content-sized skeleton cards while the room directory is loading."
  def rooms_loading_skeleton(assigns) do
    ~H"""
    <div
      id="rooms-loading"
      aria-busy="true"
      aria-label="Carregando salas"
      class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3 lg:gap-6"
    >
      <.card
        :for={idx <- 1..3}
        :key={idx}
        padding="responsive"
        bordered
        class="motion-safe:animate-pulse"
      >
        <div class="flex flex-col gap-4">
          <div class="flex items-center justify-between gap-3">
            <div class="h-6 w-40 rounded-sm bg-sunken" />
            <div class="h-6 w-16 rounded-full bg-sunken" />
          </div>
          <div class="flex items-center gap-3">
            <div class="size-6 rounded-full bg-sunken" />
            <div class="h-4 w-48 rounded-sm bg-sunken" />
          </div>
          <div class="h-4 w-32 rounded-sm bg-sunken" />
          <div class="flex justify-end">
            <div class="h-11 w-24 rounded-md bg-sunken" />
          </div>
        </div>
      </.card>
    </div>
    """
  end

  @doc "Renders the designed empty state with coiled rope motif when no rooms are open."
  def rooms_empty_state(assigns) do
    ~H"""
    <.empty_state title="Nenhuma sala aberta" class="bg-surface">
      <:illustration>
        <svg
          width="140"
          height="96"
          viewBox="0 0 140 96"
          class="shrink-0"
          fill="none"
          aria-hidden="true"
        >
          <ellipse
            cx="70"
            cy="58"
            rx="52"
            ry="26"
            class="stroke-rope-edge"
            stroke-width="11"
          />
          <ellipse
            cx="70"
            cy="58"
            rx="52"
            ry="26"
            class="stroke-rope"
            stroke-width="8"
            stroke-dasharray="4 3"
          />
          <ellipse
            cx="70"
            cy="52"
            rx="34"
            ry="16"
            class="stroke-rope-edge"
            stroke-width="11"
          />
          <ellipse
            cx="70"
            cy="52"
            rx="34"
            ry="16"
            class="stroke-rope"
            stroke-width="8"
            stroke-dasharray="4 3"
          />
          <path
            d="M104 50 C122 40 128 22 118 10"
            class="stroke-rope-edge"
            stroke-width="11"
            stroke-linecap="round"
          />
          <path
            d="M104 50 C122 40 128 22 118 10"
            class="stroke-rope"
            stroke-width="8"
            stroke-linecap="round"
            stroke-dasharray="4 3"
          />
        </svg>
      </:illustration>
      Crie uma sala e mande o link para a turma. Ela aparece aqui para todo mundo na hora.
    </.empty_state>
    """
  end

  @doc "Renders a recoverable error banner with a retry button when loading rooms fails."
  attr :message, :string, required: true

  def rooms_error_state(assigns) do
    ~H"""
    <div id="rooms-error">
      <.alert tone="danger" role="alert" title="Erro ao carregar salas">
        {@message}
        <:actions>
          <.button variant="secondary" size="sm" phx-click="retry_load">
            Tentar novamente
          </.button>
        </:actions>
      </.alert>
    </div>
    """
  end

  defp owner_color_index(name), do: :erlang.phash2(name, 6) + 1

  defp language_code(lang) when is_binary(lang) and lang != "", do: String.upcase(lang)
  defp language_code(_), do: "EN"

  defp categories_label([]), do: "Todas as categorias"

  defp categories_label(names) when length(names) <= 3 do
    Enum.join(names, ", ")
  end

  defp categories_label(names) do
    visible = names |> Enum.take(3) |> Enum.join(", ")
    "#{visible} +#{length(names) - 3}"
  end

  defp closed_note(:full), do: "Cheia"
  defp closed_note(:playing), do: "Em andamento"
  defp closed_note(:ended), do: "Acabou"
  defp closed_note(:open), do: nil
end
