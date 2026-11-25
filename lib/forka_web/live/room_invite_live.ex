defmodule ForkaWeb.RoomInviteLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias Forka.Games.RoomInvite
  alias ForkaWeb.Layouts

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case socket.assigns.current_scope do
      nil ->
        mount_preview(game_id, socket)

      scope ->
        mount_authenticated(scope, game_id, socket)
    end
  end

  defp mount_authenticated(scope, game_id, socket) do
    case Games.get_room_invite(game_id) do
      {:ok, %RoomInvite{} = invite} ->
        if Games.room_participant?(scope, invite.id) do
          {:ok, push_navigate(socket, to: ~p"/rooms/#{invite.id}")}
        else
          {:ok, assign_invite_state(socket, invite)}
        end

      {:error, reason} ->
        {:ok, assign_error_state(socket, nil, reason)}
    end
  end

  defp mount_preview(game_id, socket) do
    case Games.get_room_invite(game_id) do
      {:ok, %RoomInvite{} = invite} ->
        {:ok, assign_invite_state(socket, invite)}

      {:error, reason} ->
        {:ok, assign_error_state(socket, nil, reason)}
    end
  end

  defp assign_invite_state(socket, %RoomInvite{availability_state: :open} = invite) do
    socket
    |> assign(:page_title, invite.name)
    |> assign(:invite, invite)
    |> assign(:error_state, nil)
  end

  defp assign_invite_state(socket, %RoomInvite{availability_state: availability} = invite) do
    assign_error_state(socket, invite, availability_to_error(availability))
  end

  defp assign_error_state(socket, invite, reason) do
    socket
    |> assign(:page_title, (invite && invite.name) || "Convite inválido")
    |> assign(:invite, invite)
    |> assign(:error_state, reason)
  end

  defp availability_to_error(:full), do: :maximum_players
  defp availability_to_error(:playing), do: :game_already_started
  defp availability_to_error(:ended), do: :game_ended

  @impl true
  def handle_event(
        "join_room",
        _params,
        %{assigns: %{current_scope: nil, invite: %RoomInvite{id: id}}} = socket
      ) do
    return_to = ~p"/rooms/#{id}/join"
    {:noreply, push_navigate(socket, to: ~p"/players/log_in?return_to=#{return_to}")}
  end

  def handle_event(
        "join_room",
        _params,
        %{assigns: %{current_scope: scope, invite: %RoomInvite{id: game_id}}} = socket
      )
      when not is_nil(scope) do
    case Games.join_room(scope, game_id) do
      {:ok, _status} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{game_id}")}

      {:error, reason} ->
        invite =
          case Games.get_room_invite(game_id) do
            {:ok, fresh_invite} -> fresh_invite
            {:error, _} -> nil
          end

        {:noreply, assign_error_state(socket, invite, reason)}
    end
  end

  def handle_event("join_room", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <Layouts.subpage_header
        title={(@invite && @invite.name) || "Convite para sala"}
        back_to={~p"/"}
        back_label="Voltar para as salas"
      />

      <.card id="room-invite-card" padding="lg" bordered>
        <div class="space-y-6">
          <div :if={@invite} class="space-y-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <.badge tone={ForkaWeb.RoomComponents.room_status_tone(@invite.status)}>
                {ForkaWeb.RoomComponents.room_status_label(@invite.status)}
              </.badge>
              <span
                id="room-invite-occupancy"
                class="text-sm font-semibold text-ink-muted tabular-nums"
              >
                {@invite.player_count}/{@invite.max_players} jogadores
              </span>
            </div>

            <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <div>
                <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                  Idioma
                </dt>
                <dd id="room-invite-language" class="mt-1 text-base font-semibold text-ink">
                  {ForkaWeb.RoomComponents.room_language_label(@invite.language)}
                </dd>
              </div>
              <div>
                <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                  Categorias
                </dt>
                <dd id="room-invite-categories" class="mt-1 text-base font-semibold text-ink">
                  {ForkaWeb.RoomComponents.room_categories_label(@invite.category_names)}
                </dd>
              </div>
              <div>
                <dt class="text-xs font-extrabold uppercase tracking-wider text-ink-subtle">
                  Anfitrião
                </dt>
                <dd id="room-invite-owner" class="mt-1 text-base font-semibold text-ink">
                  {@invite.owner_username}
                </dd>
              </div>
            </dl>
          </div>

          <%= if @error_state do %>
            <div class="space-y-4">
              <div>
                <h2 class="text-lg font-bold text-ink">{error_heading(@error_state)}</h2>
                <p class="mt-1 text-sm text-ink-muted">{error_description(@error_state)}</p>
              </div>

              <div class="flex flex-wrap items-center gap-3">
                <.button
                  :if={is_nil(@current_scope) && @invite}
                  id="invite-login-link"
                  navigate={~p"/players/log_in?return_to=#{~p"/rooms/#{@invite.id}/join"}"}
                >
                  Entrar para jogar
                </.button>
                <.button id="invite-directory-link" navigate={~p"/"} variant="secondary">
                  Voltar para as salas
                </.button>
              </div>
            </div>
          <% else %>
            <%= if @current_scope do %>
              <div class="flex flex-wrap items-center gap-3">
                <.button id="invite-join-button" phx-click="join_room">
                  Entrar na sala
                </.button>
                <.button id="invite-directory-link" navigate={~p"/"} variant="secondary">
                  Voltar para as salas
                </.button>
              </div>
            <% else %>
              <div class="flex flex-wrap items-center gap-3">
                <.button
                  id="invite-login-link"
                  navigate={~p"/players/log_in?return_to=#{~p"/rooms/#{@invite.id}/join"}"}
                >
                  Entrar para jogar
                </.button>
                <.button
                  id="invite-register-link"
                  navigate={~p"/players/register?return_to=#{~p"/rooms/#{@invite.id}/join"}"}
                  variant="secondary"
                >
                  Criar conta
                </.button>
              </div>
            <% end %>
          <% end %>
        </div>
      </.card>
    </div>
    """
  end

  defp error_heading(state) when state in [:maximum_players, :full], do: "Sala cheia"

  defp error_heading(state) when state in [:game_already_started, :playing],
    do: "Partida em andamento"

  defp error_heading(state) when state in [:game_ended, :ended], do: "Partida encerrada"
  defp error_heading(:game_archived), do: "Esta sala foi arquivada"
  defp error_heading(_), do: "Sala não encontrada"

  defp error_description(state) when state in [:maximum_players, :full],
    do: "Esta sala já atingiu o limite de jogadores."

  defp error_description(state) when state in [:game_already_started, :playing],
    do: "Esta partida já começou e não aceita novos jogadores."

  defp error_description(state) when state in [:game_ended, :ended],
    do: "Esta partida já foi finalizada."

  defp error_description(:game_archived),
    do: "Esta sala não está mais disponível."

  defp error_description(_),
    do: "Não encontramos uma sala com este convite."
end
