defmodule ForkaWeb.RoomLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias ForkaWeb.Layouts

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    scope = socket.assigns.current_scope

    with :ok <- maybe_subscribe_room_lobby(socket, scope, game_id),
         {:ok, lobby} <- Games.get_room_lobby(scope, game_id) do
      {:ok,
       socket
       |> assign(:page_title, lobby.name)
       |> assign(:lobby, lobby)}
    else
      {:error, :game_archived} ->
        {:ok,
         socket
         |> put_flash(:error, "Esta sala foi arquivada.")
         |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Sala não encontrada.")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp maybe_subscribe_room_lobby(socket, scope, game_id) do
    if connected?(socket) do
      Games.subscribe_to_room_lobby(scope, game_id)
    else
      :ok
    end
  end

  @impl true
  def handle_info({:room_lobby_updated, payload}, socket) do
    case Games.room_lobby_from_payload(socket.assigns.current_scope, payload) do
      {:ok, lobby} ->
        {:noreply,
         socket
         |> assign(:page_title, lobby.name)
         |> assign(:lobby, lobby)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <Layouts.subpage_header
        title={@lobby.name}
        back_to={~p"/"}
        back_label="Voltar para as salas"
      >
        <:actions>
          <.button
            :if={@lobby.can_edit_settings?}
            id="edit-room-settings"
            variant="secondary"
            size="sm"
            navigate={~p"/salas/#{@lobby.id}/configuracoes"}
          >
            Configurações
          </.button>
        </:actions>
      </Layouts.subpage_header>

      <.card id="room-lobby-card" padding="lg" bordered>
        <div class="space-y-6">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.badge tone={status_tone(@lobby.status)}>
              {status_label(@lobby.status)}
            </.badge>
            <span id="room-lobby-occupancy" class="text-sm font-semibold text-ink-muted tabular-nums">
              {@lobby.player_count}/{@lobby.max_players} jogadores
            </span>
          </div>

          <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                Idioma das palavras
              </dt>
              <dd id="room-lobby-language" class="mt-1 text-base font-semibold text-ink">
                {language_label(@lobby.language)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                Categorias
              </dt>
              <dd id="room-lobby-categories" class="mt-1 text-base font-semibold text-ink">
                {categories_label(@lobby.category_names)}
              </dd>
            </div>
          </dl>

          <div>
            <h2 class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
              Jogadores na sala
            </h2>
            <ul id="room-lobby-players" class="mt-2 divide-y divide-line">
              <li
                :for={player <- @lobby.players}
                id={"room-lobby-player-#{player.id}"}
                class="flex items-center justify-between py-2 text-sm font-semibold text-ink"
              >
                <span>{player.username}</span>
                <span
                  :if={player.username == @lobby.owner_username}
                  class="text-xs font-extrabold uppercase text-brand-ink"
                >
                  Anfitrião
                </span>
              </li>
            </ul>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  defp status_tone(:lobby), do: "success"
  defp status_tone(:playing), do: "brand"
  defp status_tone(_status), do: "neutral"

  defp status_label(:lobby), do: "Aguardando jogadores"
  defp status_label(:playing), do: "Em andamento"
  defp status_label(:finished), do: "Finalizada"
  defp status_label(:game_over), do: "Encerrada"
  defp status_label(_status), do: "Arquivada"

  defp language_label("pt"), do: "Português"
  defp language_label("en"), do: "Inglês"
  defp language_label(other), do: other

  defp categories_label([]), do: "Todas as categorias"
  defp categories_label(names), do: Enum.join(names, ", ")
end
