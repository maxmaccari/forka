defmodule ForkaWeb.MatchLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias ForkaWeb.Layouts

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Games.get_room_lobby(scope, game_id) do
      {:ok, %{participant?: false}} ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{game_id}/join")}

      {:ok, %{status: :lobby}} ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{game_id}")}

      {:ok, room} ->
        mount_active_match(socket, scope, game_id, room)

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

  defp mount_active_match(socket, scope, game_id, initial_room) do
    if connected?(socket) do
      with :ok <- Games.subscribe_to_room_lobby(scope, game_id),
           {:ok, fresh_room} <- Games.get_room_lobby(scope, game_id) do
        route_or_assign_match(socket, fresh_room)
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
    else
      route_or_assign_match(socket, initial_room)
    end
  end

  defp route_or_assign_match(socket, %{participant?: false, id: id}) do
    {:ok, push_navigate(socket, to: ~p"/rooms/#{id}/join")}
  end

  defp route_or_assign_match(socket, %{status: :lobby, id: id}) do
    {:ok, push_navigate(socket, to: ~p"/rooms/#{id}")}
  end

  defp route_or_assign_match(socket, room) do
    {:ok,
     socket
     |> assign(:page_title, "#{room.name} · Partida")
     |> assign(:room, room)}
  end

  @impl true
  def handle_info({:room_lobby_updated, payload}, socket) do
    case Games.room_lobby_from_payload(socket.assigns.current_scope, payload) do
      {:ok, %{status: :archived}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Esta sala foi arquivada.")
         |> push_navigate(to: ~p"/")}

      {:ok, %{participant?: false}} ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      {:ok, %{status: :lobby, id: id}} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{id}")}

      {:ok, room} ->
        {:noreply,
         socket
         |> assign(:page_title, "#{room.name} · Partida")
         |> assign(:room, room)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="match-placeholder" class="mx-auto max-w-2xl">
      <Layouts.subpage_header
        title={@room.name}
        back_to={~p"/"}
        back_label="Voltar para as salas"
      />

      <.card id="match-placeholder-card" padding="lg" bordered>
        <div class="space-y-6">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.badge tone={ForkaWeb.RoomComponents.room_status_tone(@room.status)}>
              {ForkaWeb.RoomComponents.room_status_label(@room.status)}
            </.badge>
            <span class="text-sm font-semibold text-ink-muted tabular-nums">
              {@room.player_count}/{@room.max_players} jogadores
            </span>
          </div>

          <div class="space-y-2">
            <h2 class="font-display text-2xl font-bold text-ink">
              {match_heading(@room.status)}
            </h2>
            <p class="text-sm text-ink-muted">
              Você entrou na partida. O tabuleiro completo será exibido aqui nas próximas etapas.
            </p>
          </div>

          <div>
            <h3 class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
              Participantes
            </h3>
            <ul id="match-placeholder-players" class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
              <li
                :for={{player, idx} <- Enum.with_index(@room.players)}
                :key={player.id}
                class="flex min-h-12 items-center gap-3 rounded-md bg-sunken px-3 py-2"
              >
                <.avatar name={player.username} player_index={idx + 1} size="sm" />
                <span class="min-w-0 flex-1 truncate text-sm font-extrabold text-ink">
                  {player.username}
                </span>
              </li>
            </ul>
          </div>

          <div class="flex flex-wrap gap-3">
            <.button id="match-back-to-rooms" variant="secondary" navigate={~p"/"}>
              Voltar para as salas
            </.button>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  defp match_heading(:playing), do: "Partida em andamento"
  defp match_heading(:finished), do: "Partida finalizada"
  defp match_heading(:game_over), do: "Partida encerrada"
  defp match_heading(_status), do: "Partida"
end
