defmodule ForkaWeb.RoomFormLive do
  use ForkaWeb, :live_view

  alias Forka.Games
  alias Forka.Games.RoomLobby
  alias Forka.Games.RoomSettings
  alias Forka.Words
  alias ForkaWeb.Layouts

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    initial = RoomSettings.new()
    categories = Words.list_categories(language: initial.word_options.language)

    {:ok,
     socket
     |> assign(:page_title, "Criar sala")
     |> assign(:mode, :new)
     |> assign(:game_id, nil)
     |> assign(:min_players, 2)
     |> assign(:name, initial.name)
     |> assign(:max_players, initial.max_players)
     |> assign(:language, initial.word_options.language)
     |> assign(:selected_category_ids, initial.word_options.category_ids)
     |> assign(:categories, categories)
     |> assign(:form, build_form(initial, %{}, 2))}
  end

  def mount(%{"id" => game_id}, _session, %{assigns: %{live_action: :edit}} = socket) do
    scope = socket.assigns.current_scope

    case Games.get_room_settings_for_edit(scope, game_id) do
      {:ok, %{settings: settings, min_players: min_players}} ->
        mount_edit_room(socket, scope, game_id, settings, min_players)

      {:error, reason} ->
        {:ok, handle_edit_access_error(socket, game_id, reason)}
    end
  end

  defp mount_edit_room(socket, scope, game_id, initial_settings, initial_min_players) do
    if connected?(socket) do
      with :ok <- Games.subscribe_to_room_lobby(scope, game_id),
           {:ok, %{settings: fresh_settings, min_players: fresh_min_players}} <-
             Games.get_room_settings_for_edit(scope, game_id) do
        {:ok, assign_edit_form(socket, game_id, fresh_settings, fresh_min_players)}
      else
        {:error, reason} ->
          {:ok, handle_edit_access_error(socket, game_id, reason)}
      end
    else
      {:ok, assign_edit_form(socket, game_id, initial_settings, initial_min_players)}
    end
  end

  defp assign_edit_form(socket, game_id, settings, min_players) do
    categories = Words.list_categories(language: settings.word_options.language)

    socket
    |> assign(:page_title, "Configurações da sala")
    |> assign(:mode, :edit)
    |> assign(:game_id, game_id)
    |> assign(:min_players, min_players)
    |> assign(:name, settings.name)
    |> assign(:max_players, settings.max_players)
    |> assign(:language, settings.word_options.language)
    |> assign(:selected_category_ids, settings.word_options.category_ids)
    |> assign(:categories, categories)
    |> assign(:form, build_form(settings, %{}, min_players))
  end

  defp handle_edit_access_error(socket, _game_id, :game_archived) do
    socket
    |> put_flash(:error, "Esta sala foi arquivada.")
    |> push_navigate(to: ~p"/")
  end

  defp handle_edit_access_error(socket, game_id, :unauthorized) do
    socket
    |> put_flash(:error, "Apenas quem criou a sala pode editar as configurações.")
    |> push_navigate(to: ~p"/rooms/#{game_id}")
  end

  defp handle_edit_access_error(socket, game_id, :game_not_in_lobby) do
    socket
    |> put_flash(:error, "As configurações só podem ser alteradas antes da partida começar.")
    |> push_navigate(to: ~p"/rooms/#{game_id}")
  end

  defp handle_edit_access_error(socket, _game_id, _reason) do
    socket
    |> put_flash(:error, "Sala não encontrada.")
    |> push_navigate(to: ~p"/")
  end

  @impl true
  def handle_event("validate", %{"room_settings" => params}, socket) when is_map(params) do
    name =
      case Map.get(params, "name") do
        val when is_binary(val) -> val
        _ -> socket.assigns.name
      end

    {:noreply, assign_form(socket, name, :validate)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("select_max_players", %{"option" => value}, socket) do
    case Integer.parse(to_string(value)) do
      {max_players, ""} ->
        {:noreply,
         socket
         |> assign(:max_players, max_players)
         |> assign_form(socket.assigns.name, :validate)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_language", %{"option" => lang}, socket) do
    cond do
      lang == socket.assigns.language ->
        {:noreply, socket}

      lang in Games.supported_languages() ->
        categories = Words.list_categories(language: lang)

        {:noreply,
         socket
         |> assign(:language, lang)
         |> assign(:categories, categories)
         |> assign(:selected_category_ids, [])
         |> assign_form(socket.assigns.name, :validate)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_category", %{"id" => id}, socket) when is_binary(id) do
    selected = socket.assigns.selected_category_ids

    updated =
      if id in selected do
        List.delete(selected, id)
      else
        selected ++ [id]
      end

    {:noreply,
     socket
     |> assign(:selected_category_ids, updated)
     |> assign_form(socket.assigns.name, :validate)}
  end

  def handle_event("toggle_category", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("clear_categories", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_category_ids, [])
     |> assign_form(socket.assigns.name, :validate)}
  end

  def handle_event("save", %{"room_settings" => params}, %{assigns: %{mode: :new}} = socket)
      when is_map(params) do
    submit_params = normalize_submit_params(params, socket.assigns)

    case Games.create_room(socket.assigns.current_scope, submit_params) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{game.id}")}

      {:error, %Ecto.Changeset{} = cs} ->
        handle_save_error(socket, params, cs)
    end
  end

  def handle_event("save", %{"room_settings" => params}, %{assigns: %{mode: :edit}} = socket)
      when is_map(params) do
    submit_params = normalize_submit_params(params, socket.assigns)

    case Games.update_room_settings(
           socket.assigns.current_scope,
           socket.assigns.game_id,
           submit_params
         ) do
      :ok ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{socket.assigns.game_id}")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Apenas quem criou a sala pode editar as configurações.")
         |> push_navigate(to: ~p"/rooms/#{socket.assigns.game_id}")}

      {:error, :game_not_in_lobby} ->
        {:noreply,
         socket
         |> put_flash(:error, "As configurações só podem ser alteradas antes da partida começar.")
         |> push_navigate(to: ~p"/rooms/#{socket.assigns.game_id}")}

      {:error, :game_archived} ->
        {:noreply,
         socket
         |> put_flash(:error, "Esta sala foi arquivada.")
         |> push_navigate(to: ~p"/")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sala não encontrada.")
         |> push_navigate(to: ~p"/")}

      {:error, %Ecto.Changeset{} = cs} ->
        handle_save_error(socket, params, cs)
    end
  end

  def handle_event("save", _params, socket) do
    {:noreply, assign_form(socket, socket.assigns.name, :validate)}
  end

  @impl true
  def handle_info({:room_lobby_updated, payload}, %{assigns: %{mode: :edit}} = socket) do
    case Games.room_lobby_from_payload(socket.assigns.current_scope, payload) do
      {:ok, %RoomLobby{status: :archived}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Esta sala foi arquivada.")
         |> push_navigate(to: ~p"/")}

      {:ok, %RoomLobby{participant?: false}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Você saiu da sala.")
         |> push_navigate(to: ~p"/")}

      {:ok, %RoomLobby{status: status, id: id}}
      when status in [:playing, :finished, :game_over] ->
        {:noreply,
         socket
         |> put_flash(:error, "As configurações só podem ser alteradas antes da partida começar.")
         |> push_navigate(to: ~p"/rooms/#{id}/match")}

      {:ok, %RoomLobby{is_owner?: false, id: id, owner_username: owner_username}} ->
        notice =
          if is_binary(owner_username) and owner_username != "" do
            "Agora #{owner_username} comanda a sala."
          else
            "Você não comanda mais esta sala."
          end

        {:noreply,
         socket
         |> put_flash(:error, notice)
         |> push_navigate(to: ~p"/rooms/#{id}")}

      {:ok, %RoomLobby{player_count: count}} ->
        {:noreply, assign(socket, :min_players, max(2, count))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <Layouts.subpage_header
        title={@page_title}
        back_to={if(@mode == :edit, do: ~p"/rooms/#{@game_id}", else: ~p"/")}
        back_label="Voltar"
      />

      <.card id="room-form-card" padding="lg" bordered>
        <.simple_form for={@form} id="room-form" phx-change="validate" phx-submit="save">
          <.input
            field={@form[:name]}
            id="room-name"
            type="text"
            label="Nome da sala"
            placeholder="Ex.: Noite de palavras"
            maxlength="60"
            required
          />

          <input type="hidden" name="room_settings[max_players]" value={@max_players} />
          <input type="hidden" name="room_settings[word_options][language]" value={@language} />
          <input
            :for={cat_id <- @selected_category_ids}
            type="hidden"
            name="room_settings[word_options][category_ids][]"
            value={cat_id}
          />

          <div>
            <p class="mb-2 text-sm font-semibold text-ink">Limite de jogadores</p>
            <.segmented_control
              id="room-max-players"
              label="Limite de jogadores"
              value={@max_players}
              options={Enum.map(2..6, &{&1, Integer.to_string(&1)})}
              on_select="select_max_players"
              cols={5}
            />
            <p
              id="room-words-note"
              aria-live="polite"
              class="mt-2 text-xs font-semibold text-ink-subtle"
            >
              Cada jogador traz 2 palavras: com {@max_players} jogadores, são {@max_players * 2} palavras. Mínimo de 2 para começar.
            </p>
            <p
              :for={msg <- field_errors(@form, :max_players)}
              id="room-max-players-error"
              class="mt-2 text-sm font-semibold text-danger-ink"
            >
              {msg}
            </p>
          </div>

          <div>
            <p class="mb-2 text-sm font-semibold text-ink">Idioma das palavras</p>
            <.segmented_control
              id="room-language"
              label="Idioma das palavras"
              value={@language}
              options={[{"pt", "Português"}, {"en", "Inglês"}]}
              on_select="select_language"
              cols={2}
            />
            <p
              :for={msg <- word_options_errors(@form, :language)}
              id="room-language-error"
              class="mt-2 text-sm font-semibold text-danger-ink"
            >
              {msg}
            </p>
          </div>

          <div>
            <p class="mb-2 text-sm font-semibold text-ink">Categorias</p>
            <div class="flex flex-wrap gap-2">
              <.chip
                id="category-chip-all"
                pressed={@selected_category_ids == []}
                phx-click="clear_categories"
              >
                Todas as categorias
              </.chip>
              <.chip
                :for={cat <- @categories}
                id={"category-chip-#{cat.id}"}
                pressed={cat.id in @selected_category_ids}
                phx-click="toggle_category"
                phx-value-id={cat.id}
              >
                {cat.name}
              </.chip>
            </div>
            <p
              :for={msg <- word_options_errors(@form, :category_ids)}
              id="room-categories-error"
              class="mt-2 text-sm font-semibold text-danger-ink"
            >
              {msg}
            </p>
          </div>

          <:actions>
            <.button
              variant="secondary"
              navigate={if(@mode == :edit, do: ~p"/rooms/#{@game_id}", else: ~p"/")}
            >
              Cancelar
            </.button>
            <.button id="room-form-submit" phx-disable-with="Salvando...">
              {if(@mode == :edit, do: "Salvar configurações", else: "Criar sala")}
            </.button>
          </:actions>
        </.simple_form>
      </.card>
    </div>
    """
  end

  defp assign_form(socket, name, action) do
    settings = RoomSettings.new()

    attrs = %{
      "name" => name,
      "max_players" => socket.assigns.max_players,
      "word_options" => %{
        "language" => socket.assigns.language,
        "category_ids" => socket.assigns.selected_category_ids
      }
    }

    cs =
      settings
      |> Games.change_room_settings(attrs, min_players: socket.assigns.min_players)
      |> Map.put(:action, action)

    socket
    |> assign(:name, name)
    |> assign(:form, to_form(cs, as: :room_settings))
  end

  defp build_form(settings, attrs, min_players) do
    settings
    |> Games.change_room_settings(attrs, min_players: min_players)
    |> to_form(as: :room_settings)
  end

  defp normalize_submit_params(params, assigns) do
    word_options =
      case Map.fetch(params, "word_options") do
        {:ok, %{} = wo_params} ->
          %{
            "language" => Map.get(wo_params, "language", assigns.language),
            "category_ids" => Map.get(wo_params, "category_ids", [])
          }

        {:ok, invalid_wo} ->
          invalid_wo

        :error ->
          %{
            "language" => assigns.language,
            "category_ids" => []
          }
      end

    %{
      "name" => Map.get(params, "name", assigns.name),
      "max_players" => Map.get(params, "max_players", assigns.max_players),
      "word_options" => word_options
    }
  end

  defp handle_save_error(socket, params, changeset) do
    name = extract_string(Map.get(params, "name"), socket.assigns.name)
    max_players = parse_int(Map.get(params, "max_players"), socket.assigns.max_players)
    wo_params = extract_map(Map.get(params, "word_options"))
    language = extract_supported_language(Map.get(wo_params, "language"), socket.assigns.language)
    categories = Words.list_categories(language: language)

    selected_ids =
      filter_selected_categories(
        Map.get(wo_params, "category_ids"),
        categories,
        socket.assigns.selected_category_ids
      )

    {:noreply,
     socket
     |> assign(:name, name)
     |> assign(:max_players, max_players)
     |> assign(:language, language)
     |> assign(:categories, categories)
     |> assign(:selected_category_ids, selected_ids)
     |> assign(:form, to_form(%{changeset | action: :validate}, as: :room_settings))}
  end

  defp extract_string(val, _default) when is_binary(val), do: val
  defp extract_string(_val, default), do: default

  defp extract_map(%{} = val), do: val
  defp extract_map(_val), do: %{}

  defp extract_supported_language(lang, default) when is_binary(lang) do
    normalized = lang |> String.trim() |> String.downcase()
    if normalized in Games.supported_languages(), do: normalized, else: default
  end

  defp extract_supported_language(_lang, default), do: default

  defp filter_selected_categories(ids, categories, _default) when is_list(ids) do
    valid_cat_ids = MapSet.new(categories, & &1.id)

    ids
    |> Enum.filter(&(is_binary(&1) and MapSet.member?(valid_cat_ids, &1)))
    |> Enum.uniq()
  end

  defp filter_selected_categories(_ids, _categories, default), do: default

  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp parse_int(_val, default), do: default

  defp field_errors(form, field) do
    form[field].errors
    |> Enum.map(&translate_error/1)
  end

  defp word_options_errors(form, field) do
    case form.source.changes[:word_options] do
      %Ecto.Changeset{errors: errors} ->
        errors
        |> Keyword.get_values(field)
        |> Enum.map(&translate_error/1)

      _ ->
        []
    end
  end
end
