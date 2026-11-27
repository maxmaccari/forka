defmodule ForkaWeb.RoomDirectoryLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias Forka.Games.RoomListItem

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Salas")
      |> assign(:directory_limit, Games.directory_limit())
      |> assign(:capped?, false)
      |> assign(:loading?, true)
      |> assign(:refreshing?, false)
      |> assign(:needs_refresh?, false)
      |> assign(:load_error, nil)
      |> assign(:rooms_count, 0)
      |> assign(:room_order, [])
      |> assign(:room_ids, MapSet.new())
      |> assign(:pending_events, [])
      |> stream(:rooms, [])

    socket =
      if connected?(socket) do
        :ok = Games.subscribe_to_game_list()
        start_async(socket, :load_rooms, fn -> Games.list_directory_rooms_page() end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_rooms, {:ok, %{rooms: rooms, has_more?: has_more?}}, socket) do
    finish_load_rooms(socket, rooms, has_more?)
  end

  def handle_async(:load_rooms, {:ok, rooms}, socket) when is_list(rooms) do
    {page_rooms, extra} = Enum.split(rooms, socket.assigns.directory_limit)
    finish_load_rooms(socket, page_rooms, extra != [])
  end

  def handle_async(:load_rooms, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading?, false)
     |> assign(:refreshing?, false)
     |> assign(:needs_refresh?, false)
     |> assign(:load_error, "Não foi possível carregar as salas agora.")
     |> assign(:pending_events, [])}
  end

  def handle_async(:refresh_rooms, {:ok, %{rooms: rooms, has_more?: has_more?}}, socket) do
    finish_load_rooms(socket, rooms, has_more?)
  end

  def handle_async(:refresh_rooms, {:exit, _reason}, socket) do
    pending = Enum.reverse(socket.assigns.pending_events)

    socket =
      socket
      |> assign(:refreshing?, false)
      |> assign(:needs_refresh?, false)
      |> assign(:pending_events, [])

    socket =
      pending
      |> Enum.reduce(socket, &apply_room_event/2)
      |> assign(:needs_refresh?, false)

    {:noreply, socket}
  end

  defp finish_load_rooms(socket, rooms, has_more?) do
    room_order = Enum.map(rooms, & &1.id)
    room_ids = MapSet.new(room_order)
    pending = Enum.reverse(socket.assigns.pending_events)

    socket =
      socket
      |> assign(:loading?, false)
      |> assign(:refreshing?, false)
      |> assign(:needs_refresh?, false)
      |> assign(:load_error, nil)
      |> assign(:capped?, has_more?)
      |> assign(:room_order, room_order)
      |> assign(:room_ids, room_ids)
      |> assign(:rooms_count, MapSet.size(room_ids))
      |> assign(:pending_events, [])
      |> stream(:rooms, rooms, reset: true)

    socket =
      pending
      |> Enum.reduce(socket, &apply_room_event/2)
      |> maybe_start_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:game_list_updated, payload}, %{assigns: %{loading?: true}} = socket) do
    {:noreply, update(socket, :pending_events, &[payload | &1])}
  end

  def handle_info({:game_list_updated, _payload}, %{assigns: %{load_error: error}} = socket)
      when not is_nil(error) do
    {:noreply, socket}
  end

  def handle_info({:game_list_updated, payload}, %{assigns: %{refreshing?: true}} = socket) do
    {:noreply, update(socket, :pending_events, &[payload | &1])}
  end

  def handle_info({:game_list_updated, payload}, socket) do
    {:noreply, payload |> apply_room_event(socket) |> maybe_start_refresh()}
  end

  defp apply_room_event(payload, socket) do
    item = Games.room_list_item_from_event(payload)

    %{room_ids: room_ids, room_order: room_order, capped?: capped?, directory_limit: limit} =
      socket.assigns

    if RoomListItem.visible_status?(item.status) do
      apply_visible_room_event(socket, item, payload, room_ids, room_order, capped?, limit)
    else
      apply_hidden_room_event(socket, item, room_ids, room_order)
    end
  end

  defp apply_visible_room_event(socket, item, payload, room_ids, room_order, capped?, limit) do
    cond do
      MapSet.member?(room_ids, item.id) ->
        stream_insert(socket, :rooms, item)

      Map.get(payload, :action) == :repaired ->
        assign(socket, :needs_refresh?, true)

      Map.get(payload, :action) == :created or not capped? ->
        insert_new_room(socket, item, room_order, capped?, limit)

      true ->
        socket
    end
  end

  defp maybe_start_refresh(socket) do
    if Map.get(socket.assigns, :needs_refresh?, false) and
         not Map.get(socket.assigns, :refreshing?, false) and
         not Map.get(socket.assigns, :loading?, false) and
         is_nil(socket.assigns.load_error) do
      socket
      |> assign(:refreshing?, true)
      |> assign(:needs_refresh?, false)
      |> start_async(:refresh_rooms, fn -> Games.list_directory_rooms_page(repair: false) end)
    else
      socket
    end
  end

  defp insert_new_room(socket, item, room_order, capped?, limit) do
    {kept_order, evicted_ids} = Enum.split([item.id | room_order], limit)
    next_ids = MapSet.new(kept_order)

    socket =
      Enum.reduce(evicted_ids, socket, fn evicted_id, acc ->
        stream_delete_by_dom_id(acc, :rooms, "rooms-#{evicted_id}")
      end)

    socket
    |> assign(:room_order, kept_order)
    |> assign(:room_ids, next_ids)
    |> assign(:rooms_count, MapSet.size(next_ids))
    |> assign(:capped?, capped? or evicted_ids != [])
    |> stream_insert(:rooms, item, at: 0)
  end

  defp apply_hidden_room_event(socket, item, room_ids, room_order) do
    if MapSet.member?(room_ids, item.id) do
      next_order = List.delete(room_order, item.id)
      next_ids = MapSet.delete(room_ids, item.id)

      socket
      |> assign(:room_order, next_order)
      |> assign(:room_ids, next_ids)
      |> assign(:rooms_count, MapSet.size(next_ids))
      |> stream_delete_by_dom_id(:rooms, "rooms-#{item.id}")
    else
      socket
    end
  end

  @impl true
  def handle_event("retry_load", _params, socket) do
    {:noreply,
     socket
     |> assign(:loading?, true)
     |> assign(:refreshing?, false)
     |> assign(:needs_refresh?, false)
     |> assign(:load_error, nil)
     |> assign(:pending_events, [])
     |> start_async(:load_rooms, fn -> Games.list_directory_rooms_page() end)}
  end

  def handle_event("create_room", _params, %{assigns: %{current_player: nil}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/players/log_in")}
  end

  def handle_event("create_room", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/rooms/new")}
  end

  def handle_event("join_room", %{"id" => game_id}, %{assigns: %{current_player: nil}} = socket)
      when is_binary(game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, valid_id} ->
        return_to = ~p"/rooms/#{valid_id}/join"
        {:noreply, push_navigate(socket, to: ~p"/players/log_in?return_to=#{return_to}")}

      :error ->
        {:noreply, push_navigate(socket, to: ~p"/players/log_in")}
    end
  end

  def handle_event("join_room", _params, %{assigns: %{current_player: nil}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/players/log_in")}
  end

  def handle_event("join_room", %{"id" => game_id}, socket) when is_binary(game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, valid_id} ->
        case Games.join_room(socket.assigns.current_scope, valid_id) do
          {:ok, _status} ->
            {:noreply, push_navigate(socket, to: ~p"/rooms/#{valid_id}")}

          {:error, :game_archived} ->
            {:noreply,
             socket
             |> apply_hidden_room_event(
               %RoomListItem{id: valid_id, status: :archived},
               socket.assigns.room_ids,
               socket.assigns.room_order
             )
             |> put_flash(:error, "Esta sala foi arquivada.")}

          {:error, _reason} ->
            {:noreply, push_navigate(socket, to: ~p"/rooms/#{valid_id}/join")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Sala não encontrada.")}
    end
  end

  def handle_event("join_room", _params, socket) do
    {:noreply, put_flash(socket, :error, "Sala não encontrada.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="flex flex-col gap-6 pb-24 sm:pb-0">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div class="flex flex-col gap-1">
          <h1 class="font-display text-3xl font-bold tracking-tight text-ink sm:text-4xl">
            Salas
          </h1>
          <p
            id="rooms-live-status"
            aria-live="polite"
            class="flex items-center gap-2 text-sm font-semibold text-ink-subtle"
          >
            <span
              aria-hidden="true"
              class={[
                "size-2 shrink-0 rounded-full",
                if(@load_error != nil, do: "bg-danger-ink", else: "bg-success-ink")
              ]}
            />
            <span>
              <%= cond do %>
                <% @loading? -> %>
                  Carregando salas...
                <% @load_error != nil -> %>
                  Sem conexão com a lista
                <% true -> %>
                  Ao vivo · {count_label(@rooms_count)}<span :if={@capped?}> · mostrando as {@directory_limit} mais recentes</span><span class="hidden sm:inline"> · a lista se atualiza sozinha</span>
              <% end %>
            </span>
          </p>
        </div>

        <div class="hidden sm:block">
          <%= if @current_player do %>
            <.button id="create-room-desktop" phx-click="create_room">
              <.icon name="hero-plus-mini" class="size-5" /> Criar sala
            </.button>
          <% else %>
            <.button id="create-room-desktop" navigate={~p"/players/log_in"}>
              <.icon name="hero-plus-mini" class="size-5" /> Criar sala
            </.button>
          <% end %>
        </div>
      </div>

      <%= cond do %>
        <% @loading? -> %>
          <.rooms_loading_skeleton />
        <% @load_error != nil -> %>
          <.rooms_error_state message={@load_error} />
        <% true -> %>
          <div :if={@rooms_count == 0} id="rooms-empty">
            <.rooms_empty_state />
          </div>

          <div
            id="rooms-list"
            phx-update="stream"
            class={[
              "grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3 lg:gap-6",
              @rooms_count == 0 && "hidden"
            ]}
          >
            <.room_card
              :for={{dom_id, room} <- @streams.rooms}
              id={dom_id}
              room={room}
              current_player={@current_player}
            />
          </div>
      <% end %>

      <div class="fixed inset-x-0 bottom-0 z-20 border-t border-line bg-canvas px-4 py-3 sm:hidden">
        <%= if @current_player do %>
          <.button id="create-room-mobile" phx-click="create_room" full>
            <.icon name="hero-plus-mini" class="size-5" /> Criar sala
          </.button>
        <% else %>
          <.button id="create-room-mobile" navigate={~p"/players/log_in"} full>
            <.icon name="hero-plus-mini" class="size-5" /> Criar sala
          </.button>
        <% end %>
      </div>
    </section>
    """
  end

  defp count_label(0), do: "nenhuma sala"
  defp count_label(1), do: "1 sala"
  defp count_label(count), do: "#{count} salas"
end
