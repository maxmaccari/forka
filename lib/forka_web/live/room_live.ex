defmodule ForkaWeb.RoomLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias Forka.Games.RoomLobby

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Games.get_room_lobby(scope, game_id) do
      {:ok, %RoomLobby{participant?: false}} ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{game_id}/join")}

      {:ok, %RoomLobby{status: status}} when status in [:playing, :finished, :game_over] ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{game_id}/match")}

      {:ok, %RoomLobby{} = lobby} ->
        mount_lobby_participant(socket, scope, game_id, lobby)

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

  defp mount_lobby_participant(socket, scope, game_id, initial_lobby) do
    if connected?(socket) do
      with :ok <- Games.subscribe_to_room_lobby(scope, game_id),
           {:ok, fresh_lobby} <- Games.get_room_lobby(scope, game_id) do
        route_or_assign_lobby(socket, fresh_lobby)
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
      route_or_assign_lobby(socket, initial_lobby)
    end
  end

  defp route_or_assign_lobby(socket, %RoomLobby{participant?: false, id: id}) do
    {:ok, push_navigate(socket, to: ~p"/rooms/#{id}/join")}
  end

  defp route_or_assign_lobby(socket, %RoomLobby{status: status, id: id})
       when status in [:playing, :finished, :game_over] do
    {:ok, push_navigate(socket, to: ~p"/rooms/#{id}/match")}
  end

  defp route_or_assign_lobby(socket, %RoomLobby{} = lobby) do
    {:ok,
     socket
     |> assign(:page_title, lobby.name)
     |> assign(:lobby, lobby)
     |> assign(:invite_url, url(~p"/rooms/#{lobby.id}/join"))
     |> assign(:lobby_notice, nil)
     |> assign(:confirm_leave?, false)}
  end

  @impl true
  def handle_event("leave_room", _params, socket),
    do: leave_room(socket, confirmed?: false)

  def handle_event("confirm_leave_room", _params, socket),
    do: leave_room(socket, confirmed?: true)

  def handle_event("cancel_leave_room", _params, socket),
    do: {:noreply, assign(socket, :confirm_leave?, false)}

  # Players are sorted by seat, so the first other player is the lowest remaining seat.
  defp next_owner_username(%RoomLobby{players: players}, viewer_id) do
    case Enum.find(players, &(&1.id != viewer_id)) do
      nil -> nil
      player -> player.username
    end
  end

  defp leave_room(socket, opts) do
    game_id = socket.assigns.lobby.id

    case Games.leave_game(socket.assigns.current_scope, game_id, opts) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Você saiu da sala.")
         |> push_navigate(to: ~p"/")}

      {:error, {:confirmation_required, %RoomLobby{} = current_lobby}} ->
        {:noreply,
         socket
         |> apply_lobby_update(current_lobby)
         |> assign(:confirm_leave?, true)}

      {:error, :game_already_started} ->
        {:noreply,
         socket
         |> put_flash(:info, "A partida já começou.")
         |> push_navigate(to: ~p"/rooms/#{game_id}/match")}

      {:error, :game_archived} ->
        {:noreply,
         socket
         |> put_flash(:error, "Esta sala foi arquivada.")
         |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:room_lobby_updated, payload}, socket) do
    case Games.room_lobby_from_payload(socket.assigns.current_scope, payload) do
      {:ok, %RoomLobby{status: :archived}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Esta sala foi arquivada.")
         |> push_navigate(to: ~p"/")}

      {:ok, %RoomLobby{status: status, participant?: true, id: id}}
      when status in [:playing, :finished, :game_over] ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{id}/match")}

      {:ok, %RoomLobby{participant?: false}} ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      {:ok, %RoomLobby{} = lobby} ->
        {:noreply,
         socket
         |> apply_lobby_update(lobby)
         |> assign(:confirm_leave?, socket.assigns.confirm_leave? and lobby.is_owner?)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp apply_lobby_update(socket, %RoomLobby{} = lobby) do
    notice =
      ownership_change_notice(socket.assigns.lobby, lobby) || socket.assigns.lobby_notice

    socket
    |> assign(:page_title, lobby.name)
    |> assign(:lobby, lobby)
    |> assign(:lobby_notice, notice)
  end

  defp ownership_change_notice(
         %RoomLobby{owner_id: old_owner_id},
         %RoomLobby{owner_id: new_owner_id, is_owner?: true}
       )
       when old_owner_id != new_owner_id and not is_nil(new_owner_id) do
    "Agora você comanda a sala."
  end

  defp ownership_change_notice(
         %RoomLobby{owner_id: old_owner_id},
         %RoomLobby{owner_id: new_owner_id, owner_username: username}
       )
       when old_owner_id != new_owner_id and not is_nil(new_owner_id) and username != "" do
    "Agora #{username} comanda a sala."
  end

  defp ownership_change_notice(_previous, _current), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 items-start gap-6 md:grid-cols-3">
      <div class="flex flex-col gap-6 md:col-span-2">
        <div class="flex items-start gap-3">
          <.icon_button icon="hero-arrow-left" aria_label="Voltar para as salas" navigate={~p"/"} />
          <div class="min-w-0 flex-1 space-y-1">
            <p class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
              Sala de espera
            </p>
            <div class="flex flex-wrap items-center gap-3">
              <h1 class="truncate font-display text-3xl font-bold leading-tight text-ink sm:text-4xl">
                {@lobby.name}
              </h1>
              <.badge tone={ForkaWeb.RoomComponents.room_status_tone(@lobby.status)}>
                {ForkaWeb.RoomComponents.room_status_label(@lobby.status)}
              </.badge>
            </div>
          </div>
        </div>

        <.lobby_invite_card
          id="room-invite-card"
          invite_url={@invite_url}
          room_name={@lobby.name}
        />

        <.word_availability_alert
          :if={
            @lobby.status == :lobby and @lobby.word_availability != nil and
              not @lobby.word_availability.enough_words?
          }
          id="room-word-availability-alert"
          availability={@lobby.word_availability}
          settings_path={
            if(@lobby.can_edit_settings?, do: ~p"/rooms/#{@lobby.id}/settings", else: nil)
          }
        />

        <.lobby_roster
          players={@lobby.players}
          owner_id={@lobby.owner_id}
          current_player_id={@current_scope.player.id}
          empty_seats={@lobby.empty_seats}
          player_count={@lobby.player_count}
          max_players={@lobby.max_players}
          word_availability={@lobby.word_availability}
        />
      </div>

      <aside class="flex flex-col gap-4">
        <.card id="room-settings-card" padding="md" bordered>
          <div class="space-y-4">
            <div class="flex items-center justify-between gap-2">
              <h2 class="font-display text-xl font-bold text-ink">Configurações</h2>
              <.button
                :if={@lobby.can_edit_settings?}
                id="edit-room-settings"
                variant="link"
                size="sm"
                navigate={~p"/rooms/#{@lobby.id}/settings"}
              >
                Editar
              </.button>
            </div>

            <dl class="grid grid-cols-1 gap-3 text-sm">
              <div>
                <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                  Idioma das palavras
                </dt>
                <dd id="room-lobby-language" class="mt-1 text-base font-semibold text-ink">
                  {ForkaWeb.RoomComponents.room_language_label(@lobby.language)}
                </dd>
              </div>
              <div>
                <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                  Categorias
                </dt>
                <dd id="room-lobby-categories" class="mt-1 text-base font-semibold text-ink">
                  {ForkaWeb.RoomComponents.room_categories_label(@lobby.category_names)}
                </dd>
              </div>
              <div>
                <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                  Ocupação
                </dt>
                <dd
                  id="room-lobby-occupancy"
                  class="mt-1 text-base font-semibold text-ink tabular-nums"
                >
                  {@lobby.player_count}/{@lobby.max_players} jogadores
                </dd>
              </div>
            </dl>
          </div>
        </.card>

        <.lobby_waiting_status
          is_owner?={@lobby.is_owner?}
          owner_username={@lobby.owner_username}
          player_count={@lobby.player_count}
          word_availability={@lobby.word_availability}
        />

        <.status_toast
          :if={@lobby_notice}
          id="room-lobby-notice"
          tone="hero"
          class="w-full justify-center"
        >
          {@lobby_notice}
        </.status_toast>

        <.button
          :if={@lobby.can_leave?}
          id="leave-room-button"
          type="button"
          variant="danger-link"
          phx-click="leave_room"
          phx-disable-with="Saindo..."
          full
        >
          Sair da sala
        </.button>

        <.modal
          :if={@confirm_leave?}
          id="leave-room-confirm"
          show
          role="alertdialog"
          on_cancel={JS.push("cancel_leave_room")}
        >
          <:title>Sair da sala?</:title>
          <:description>
            <%= case next_owner_username(@lobby, @current_scope.player.id) do %>
              <% nil -> %>
                Você é a última pessoa na sala. Ao sair, ela será arquivada.
              <% next_owner -> %>
                A sala passa para {next_owner}.
            <% end %>
          </:description>
          <p
            :if={next_owner_username(@lobby, @current_scope.player.id)}
            class="text-sm text-ink-muted"
          >
            Você pode voltar pelo link de convite.
          </p>
          <:actions>
            <.button
              id="cancel-leave-room"
              type="button"
              variant="secondary"
              phx-click="cancel_leave_room"
            >
              Cancelar
            </.button>
            <.button
              id="confirm-leave-room"
              type="button"
              variant="danger"
              phx-click="confirm_leave_room"
              phx-disable-with="Saindo..."
            >
              {if(next_owner_username(@lobby, @current_scope.player.id),
                do: "Sair e passar a sala",
                else: "Sair e arquivar a sala"
              )}
            </.button>
          </:actions>
        </.modal>
      </aside>
    </div>
    """
  end
end
