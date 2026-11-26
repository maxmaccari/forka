defmodule ForkaWeb.RoomComponents do
  @moduledoc """
  Domain presentation components for Forka's live room directory.

  Maps `Forka.Games.RoomListItem` read models to Forka UI primitives and semantic tokens.
  """
  use Phoenix.Component
  use ForkaWeb, :verified_routes

  import ForkaWeb.CoreComponents

  alias Forka.Games.RoomListItem
  alias Forka.Games.WordAvailability

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
              navigate={~p"/rooms/#{@room.id}/join"}
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

  @doc "Returns the badge tone for a room status."
  def room_status_tone(:lobby), do: "success"
  def room_status_tone(:playing), do: "brand"
  def room_status_tone(_status), do: "neutral"

  @doc "Returns the human-readable Portuguese label for a room status."
  def room_status_label(:lobby), do: "Aguardando jogadores"
  def room_status_label(:playing), do: "Em andamento"
  def room_status_label(:finished), do: "Finalizada"
  def room_status_label(:game_over), do: "Encerrada"
  def room_status_label(_status), do: "Arquivada"

  @doc "Returns the human-readable Portuguese label for a room language code."
  def room_language_label("pt"), do: "Português"
  def room_language_label("en"), do: "Inglês"
  def room_language_label(other), do: other

  @doc "Formats category names for room lobby and invite details."
  def room_categories_label([]), do: "Todas as categorias"
  def room_categories_label(names), do: Enum.join(names, ", ")

  @doc """
  Formats the human-readable pt-BR explanation for an insufficient word pool, including
  actionable guidance on how to broaden the selection.
  """
  def insufficient_words_message(%WordAvailability{} = availability) do
    count_label = valid_words_count_label(availability.available_words)

    requirement_part =
      if availability.player_count < 2 do
        "são necessárias pelo menos #{availability.required_words} (2 por jogador, mínimo de 2 jogadores)"
      else
        "são necessárias #{availability.required_words} (2 por jogador)"
      end

    guidance = broaden_guidance(availability.broaden_actions)
    "Esta seleção tem #{count_label}, mas #{requirement_part}. #{guidance}"
  end

  @doc "Renders the warning alert when a room's word pool is smaller than required for kickoff."
  attr :id, :string, required: true
  attr :availability, WordAvailability, required: true
  attr :settings_path, :string, default: nil
  attr :role, :string, default: "alert", values: ~w(alert status)
  attr :title, :string, default: "Poucas palavras para começar"

  def word_availability_alert(assigns) do
    assigns = assign(assigns, :message, insufficient_words_message(assigns.availability))

    ~H"""
    <div id={@id}>
      <.alert tone="warning" role={@role} title={@title}>
        {@message}
        <:actions :if={@settings_path}>
          <.button
            id="broaden-word-selection"
            variant="secondary"
            size="sm"
            navigate={@settings_path}
          >
            Ajustar configurações
          </.button>
        </:actions>
      </.alert>
    </div>
    """
  end

  @doc "Formats the Sala.dc.html word-requirement summary line for a lobby."
  def room_words_requirement_label(player_count, max_players, required_words) do
    "#{player_count} de #{max_players} · #{required_words} palavras (2 por jogador)"
  end

  @doc "Renders the lobby invite link card with read-only URL, copy button, and progressive share button."
  attr :id, :string, default: "room-invite-card"
  attr :invite_url, :string, required: true
  attr :room_name, :string, required: true

  def lobby_invite_card(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-heading"}
      phx-hook="ShareInvite"
      data-url={@invite_url}
      data-title={@room_name}
      class="rounded-lg bg-surface p-4 text-ink shadow-2 ring-1 ring-line dark:shadow-none sm:p-6"
    >
      <div class="flex flex-col gap-3">
        <div class="flex flex-col gap-1">
          <h2 id={"#{@id}-heading"} class="text-base font-extrabold text-ink">
            Chame a turma pelo link
          </h2>
          <p class="text-sm text-ink-subtle">
            Envie este endereço para convidar amigos para a sala.
          </p>
        </div>

        <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
          <label for="room-invite-url" class="sr-only">Link de convite da sala</label>
          <input
            id="room-invite-url"
            type="text"
            readonly
            value={@invite_url}
            class="min-h-11 min-w-0 flex-1 rounded-md bg-sunken px-3 py-2 text-sm font-semibold text-ink ring-1 ring-inset ring-line-strong"
          />
          <div class="flex shrink-0 items-center gap-2">
            <.button
              id="copy-invite-link"
              type="button"
              variant="secondary"
              size="sm"
              data-copy-invite
            >
              <.icon name="hero-clipboard-document-mini" class="size-5" />
              Copiar link
            </.button>
            <.button
              id="share-invite-link"
              type="button"
              variant="secondary"
              size="sm"
              data-share-invite
              class="hidden"
            >
              <.icon name="hero-share-mini" class="size-5" />
              Compartilhar
            </.button>
          </div>
        </div>

        <p
          id="copy-invite-status"
          data-share-status
          aria-live="polite"
          class="min-h-6 text-sm font-bold text-success-ink"
        >
        </p>
      </div>
    </section>
    """
  end

  @doc "Renders the lobby player roster, owner badge, viewer marker, word requirement, and open seats."
  attr :players, :list, required: true
  attr :owner_id, :string, default: nil
  attr :current_player_id, :string, required: true
  attr :empty_seats, :integer, required: true
  attr :player_count, :integer, required: true
  attr :max_players, :integer, required: true
  attr :word_availability, :any, default: nil

  def lobby_roster(assigns) do
    ~H"""
    <section aria-labelledby="room-lobby-players-heading" class="flex flex-col gap-3">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="room-lobby-players-heading" class="font-display text-xl font-bold text-ink">
          Jogadores
        </h2>
        <p
          :if={@word_availability}
          id="room-lobby-words-requirement"
          class="text-sm font-bold text-ink-muted tabular-nums"
        >
          {room_words_requirement_label(
            @player_count,
            @max_players,
            @word_availability.required_words
          )}
        </p>
      </div>

      <.card id="room-lobby-roster-card" padding="sm" bordered>
        <ul id="room-lobby-players" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <li
            :for={{player, idx} <- Enum.with_index(@players)}
            :key={player.id}
            id={"room-lobby-player-#{player.id}"}
            class="flex min-h-12 items-center gap-3 rounded-md bg-sunken px-3 py-2"
          >
            <.avatar name={player.username} player_index={idx + 1} size="sm" />
            <span class="min-w-0 flex-1 truncate text-sm font-extrabold text-ink">
              {player.username}<span
                :if={player.id == @current_player_id}
                class="font-normal text-ink-subtle"
              > · você</span>
            </span>
            <.badge :if={player.id == @owner_id} tone="accent">
              Anfitrião
            </.badge>
          </li>

          <li
            :for={seat <- Range.new(1, @empty_seats, 1)}
            :key={"empty-#{seat}"}
            id={"room-lobby-empty-seat-#{seat}"}
            class="flex min-h-12 items-center gap-3 rounded-md px-3 py-2 ring-2 ring-inset ring-line"
          >
            <span
              aria-hidden="true"
              class="inline-flex size-8 shrink-0 rounded-full border-2 border-dashed border-line-strong"
            />
            <span class="text-sm italic text-ink-subtle">Lugar livre</span>
          </li>
        </ul>
      </.card>
    </section>
    """
  end

  @doc "Renders the role-aware lobby waiting/readiness status box."
  attr :is_owner?, :boolean, required: true
  attr :owner_username, :string, required: true
  attr :player_count, :integer, required: true
  attr :word_availability, :any, default: nil

  def lobby_waiting_status(assigns) do
    ~H"""
    <p
      id="room-waiting-status"
      role="status"
      class="flex min-h-12 items-center justify-center gap-3 rounded-md bg-sunken px-4 py-3 text-center text-sm font-extrabold text-ink-muted ring-2 ring-inset ring-line"
    >
      <%= cond do %>
        <% not @is_owner? -> %>
          <span>Esperando {@owner_username} começar</span>
          <span class="forka-dots inline-flex items-center gap-1" aria-hidden="true">
            <i /><i /><i />
          </span>
        <% @player_count < 2 -> %>
          <span>Aguardando pelo menos mais 1 jogador para começar</span>
          <span class="forka-dots inline-flex items-center gap-1" aria-hidden="true">
            <i /><i /><i />
          </span>
        <% @word_availability != nil and not @word_availability.enough_words? -> %>
          <span>Ajuste as configurações para ter palavras suficientes.</span>
        <% true -> %>
          <span>
            Sala pronta com {@player_count} jogadores ({(@word_availability && @word_availability.required_words) || @player_count * 2} palavras).
          </span>
      <% end %>
    </p>
    """
  end

  defp valid_words_count_label(1), do: "1 palavra válida"
  defp valid_words_count_label(count), do: "#{count} palavras válidas"

  defp broaden_guidance([:add_categories, :all_categories, :change_language]) do
    ~s(Para ampliar o banco de palavras, escolha mais categorias, selecione "Todas as categorias" ou troque o idioma nas configurações da sala.)
  end

  defp broaden_guidance([:change_language, :fewer_players]) do
    "Como todas as categorias já estão incluídas, troque o idioma nas configurações da sala ou jogue com menos jogadores."
  end

  defp broaden_guidance(_actions) do
    "Como todas as categorias já estão incluídas, troque o idioma nas configurações da sala."
  end
end
