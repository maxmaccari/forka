defmodule ForkaWeb.RoomInviteLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias Forka.Games.RoomInvite
  alias ForkaWeb.Layouts

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case socket.assigns.current_scope do
      nil ->
        mount_guest(game_id, socket)

      scope ->
        mount_authenticated(scope, game_id, socket)
    end
  end

  defp mount_authenticated(scope, game_id, socket) do
    case Games.join_room(scope, game_id) do
      {:ok, _status} ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{game_id}")}

      {:error, reason} ->
        case Games.get_room_invite(game_id) do
          {:ok, invite} ->
            {:ok,
             socket
             |> assign(:page_title, invite.name)
             |> assign(:invite, invite)
             |> assign(:error_state, reason)}

          {:error, _invite_reason} ->
            {:ok,
             socket
             |> assign(:page_title, "Convite inválido")
             |> assign(:invite, nil)
             |> assign(:error_state, reason)}
        end
    end
  end

  defp mount_guest(game_id, socket) do
    case Games.get_room_invite(game_id) do
      {:ok, %RoomInvite{availability_state: :open} = invite} ->
        {:ok,
         socket
         |> assign(:page_title, invite.name)
         |> assign(:invite, invite)
         |> assign(:error_state, nil)}

      {:ok, %RoomInvite{availability_state: availability} = invite} ->
        {:ok,
         socket
         |> assign(:page_title, invite.name)
         |> assign(:invite, invite)
         |> assign(:error_state, availability_to_error(availability))}

      {:error, reason} ->
        {:ok,
         socket
         |> assign(:page_title, "Convite inválido")
         |> assign(:invite, nil)
         |> assign(:error_state, reason)}
    end
  end

  defp availability_to_error(:full), do: :maximum_players
  defp availability_to_error(:playing), do: :game_already_started
  defp availability_to_error(:ended), do: :game_ended

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
