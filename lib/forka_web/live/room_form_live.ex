defmodule ForkaWeb.RoomFormLive do
  use ForkaWeb, :live_view

  alias Forka.Games
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
    case Games.get_room_settings_for_edit(socket.assigns.current_scope, game_id) do
      {:ok, %{settings: settings, min_players: min_players}} ->
        categories = Words.list_categories(language: settings.word_options.language)

        {:ok,
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
         |> assign(:form, build_form(settings, %{}, min_players))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Sala não encontrada.")
         |> push_navigate(to: ~p"/")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Apenas quem criou a sala pode editar as configurações.")
         |> push_navigate(to: ~p"/salas/#{game_id}")}

      {:error, :game_not_in_lobby} ->
        {:ok,
         socket
         |> put_flash(:error, "As configurações só podem ser alteradas antes da partida começar.")
         |> push_navigate(to: ~p"/salas/#{game_id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"room_settings" => params}, socket) do
    name = Map.get(params, "name", socket.assigns.name)
    {:noreply, assign_form(socket, name, :validate)}
  end

  def handle_event("select_max_players", %{"value" => value}, socket) do
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

  def handle_event("select_language", %{"value" => lang}, socket) do
    if lang in Games.supported_languages() do
      categories = Words.list_categories(language: lang)

      {:noreply,
       socket
       |> assign(:language, lang)
       |> assign(:categories, categories)
       |> assign(:selected_category_ids, [])
       |> assign_form(socket.assigns.name, :validate)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_category", %{"id" => id}, socket) do
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

  def handle_event("clear_categories", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_category_ids, [])
     |> assign_form(socket.assigns.name, :validate)}
  end

  def handle_event("save", %{"room_settings" => params}, %{assigns: %{mode: :new}} = socket) do
    submit_params = normalize_submit_params(params, socket.assigns)

    case Games.create_room(socket.assigns.current_scope, submit_params) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/salas/#{game.id}")}

      {:error, %Ecto.Changeset{} = cs} ->
        handle_save_error(socket, params, cs)
    end
  end

  def handle_event("save", %{"room_settings" => params}, %{assigns: %{mode: :edit}} = socket) do
    submit_params = normalize_submit_params(params, socket.assigns)

    case Games.update_room_settings(
           socket.assigns.current_scope,
           socket.assigns.game_id,
           submit_params
         ) do
      :ok ->
        {:noreply, push_navigate(socket, to: ~p"/salas/#{socket.assigns.game_id}")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Apenas quem criou a sala pode editar as configurações.")
         |> push_navigate(to: ~p"/salas/#{socket.assigns.game_id}")}

      {:error, :game_not_in_lobby} ->
        {:noreply,
         socket
         |> put_flash(:error, "As configurações só podem ser alteradas antes da partida começar.")
         |> push_navigate(to: ~p"/salas/#{socket.assigns.game_id}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sala não encontrada.")
         |> push_navigate(to: ~p"/")}

      {:error, %Ecto.Changeset{} = cs} ->
        handle_save_error(socket, params, cs)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <Layouts.subpage_header
        title={@page_title}
        back_to={if(@mode == :edit, do: ~p"/salas/#{@game_id}", else: ~p"/")}
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
              navigate={if(@mode == :edit, do: ~p"/salas/#{@game_id}", else: ~p"/")}
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
    wo_params = Map.get(params, "word_options", %{})

    %{
      "name" => Map.get(params, "name", assigns.name),
      "max_players" => Map.get(params, "max_players", assigns.max_players),
      "word_options" => %{
        "language" => Map.get(wo_params, "language", assigns.language),
        "category_ids" => Map.get(wo_params, "category_ids", [])
      }
    }
  end

  defp handle_save_error(socket, params, changeset) do
    name = Map.get(params, "name", socket.assigns.name)
    max_players = parse_int(Map.get(params, "max_players"), socket.assigns.max_players)
    wo_params = Map.get(params, "word_options", %{})
    language = Map.get(wo_params, "language", socket.assigns.language)
    categories = Words.list_categories(language: language)
    valid_cat_ids = MapSet.new(categories, & &1.id)

    selected_ids =
      wo_params
      |> Map.get("category_ids", socket.assigns.selected_category_ids)
      |> Enum.filter(&MapSet.member?(valid_cat_ids, &1))

    {:noreply,
     socket
     |> assign(:name, name)
     |> assign(:max_players, max_players)
     |> assign(:language, language)
     |> assign(:categories, categories)
     |> assign(:selected_category_ids, selected_ids)
     |> assign(:form, to_form(%{changeset | action: :validate}, as: :room_settings))}
  end

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
