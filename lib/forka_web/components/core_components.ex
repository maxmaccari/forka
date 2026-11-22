defmodule ForkaWeb.CoreComponents do
  @moduledoc """
  Provides core UI components for Forka player screens and shared helpers.

  All player-facing primitives use Forka semantic tokens (`canvas`, `surface`,
  `sunken`, `ink`, `brand`, `hero`, `accent`, `success`, `warning`, `danger`)
  defined in `assets/css/app.css`. Icons are provided by Heroicons via `icon/1`.
  """
  use Phoenix.Component
  use Gettext, backend: ForkaWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal dialog.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :role, :string, default: "dialog", values: ~w(dialog alertdialog)
  attr :on_cancel, JS, default: %JS{}
  slot :title
  slot :description
  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-hero/60 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role={@role}
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div class="w-full max-w-xl sm:p-6">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden rounded-xl bg-surface p-6 text-ink shadow-5 ring-1 ring-line transition dark:shadow-none sm:p-8"
            >
              <div class="absolute top-4 right-4">
                <.icon_button
                  icon="hero-x-mark-solid"
                  aria_label={gettext("close")}
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                />
              </div>
              <div id={"#{@id}-content"}>
                <h2
                  :if={@title != []}
                  id={"#{@id}-title"}
                  class="pr-12 font-display text-xl font-bold text-ink"
                >
                  {render_slot(@title)}
                </h2>
                <p
                  :if={@description != []}
                  id={"#{@id}-description"}
                  class="mt-2 text-sm text-ink-muted"
                >
                  {render_slot(@description)}
                </p>
                <div class={@title != [] && "mt-4"}>
                  {render_slot(@inner_block)}
                </div>
                <div :if={@actions != []} class="mt-6 flex flex-wrap justify-end gap-3">
                  {render_slot(@actions)}
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders an anchored bottom sheet for game moments and mobile-first confirmations.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :tone, :string, default: "hero", values: ~w(hero light)
  attr :role, :string, default: "dialog", values: ~w(dialog alertdialog)
  attr :on_cancel, JS, default: %JS{}
  slot :title
  slot :description
  slot :inner_block, required: true
  slot :actions

  def bottom_sheet(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-hero/60 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 flex items-end justify-center p-3"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role={@role}
        aria-modal="true"
        tabindex="0"
      >
        <.focus_wrap
          id={"#{@id}-container"}
          phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
          phx-key="escape"
          phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
          class={[
            "forka-pop relative hidden w-full max-w-lg max-h-full overflow-y-auto rounded-xl shadow-5 ring-1 transition dark:shadow-none",
            if(@tone == "hero",
              do: "bg-hero text-hero-ink ring-line/20",
              else: "bg-surface text-ink ring-line"
            )
          ]}
        >
          <div id={"#{@id}-content"}>
            <div class={[
              "sticky top-0 z-10 flex items-start justify-between gap-4 px-6 pt-6 pb-3",
              if(@tone == "hero", do: "bg-hero", else: "bg-surface")
            ]}>
              <div class="min-w-0 flex-1">
                <h2
                  :if={@title != []}
                  id={"#{@id}-title"}
                  class="font-display text-2xl font-bold"
                >
                  {render_slot(@title)}
                </h2>
                <p
                  :if={@description != []}
                  id={"#{@id}-description"}
                  class={[
                    "mt-2 text-sm",
                    if(@tone == "hero", do: "text-hero-muted", else: "text-ink-muted")
                  ]}
                >
                  {render_slot(@description)}
                </p>
              </div>
              <button
                type="button"
                phx-click={JS.exec("data-cancel", to: "##{@id}")}
                aria-label={gettext("close")}
                class={[
                  "inline-flex size-11 shrink-0 items-center justify-center rounded-md transition-colors",
                  if(@tone == "hero",
                    do: "text-hero-muted hover:bg-hero-2 hover:text-hero-ink",
                    else: "text-ink-muted hover:bg-sunken hover:text-ink"
                  )
                ]}
              >
                <.icon name="hero-x-mark-solid" class="size-5" />
              </button>
            </div>
            <div class="px-6 pb-6">
              <div class={@title != [] && "mt-2"}>
                {render_slot(@inner_block)}
              </div>
              <div :if={@actions != []} class="mt-6 flex flex-wrap justify-end gap-3">
                {render_slot(@actions)}
              </div>
            </div>
          </div>
        </.focus_wrap>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-3 right-3 z-50 w-80 rounded-lg p-4 shadow-3 ring-2 ring-inset dark:shadow-none sm:w-96",
        @kind == :info && "bg-success-soft text-success-ink ring-success-ink",
        @kind == :error && "bg-danger-soft text-danger-ink ring-danger-ink"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-2 pr-8 text-sm font-bold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="size-5 shrink-0" />
        {@title}
      </p>
      <p class="mt-1 pr-8 text-sm leading-6">{msg}</p>
      <button
        type="button"
        class="group absolute top-1 right-1 inline-flex size-11 items-center justify-center rounded-md opacity-70 hover:opacity-100"
        aria-label={gettext("close")}
      >
        <.icon name="hero-x-mark-solid" class="size-5" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="size-4 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="size-4 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders an inline alert banner.
  """
  attr :tone, :string, default: "info", values: ~w(info success warning danger)
  attr :title, :string, default: nil
  attr :role, :string, default: "status", values: ~w(status alert)
  attr :class, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def alert(assigns) do
    ~H"""
    <div
      role={@role}
      class={[
        "flex items-start gap-3 rounded-lg p-4 ring-2 ring-inset",
        alert_tone_class(@tone),
        @class
      ]}
    >
      <.icon name={alert_icon(@tone)} class="size-5 shrink-0" />
      <div class="min-w-0 flex-1">
        <p :if={@title} class="text-sm font-bold">{@title}</p>
        <div class="text-sm leading-6">{render_slot(@inner_block)}</div>
        <div :if={@actions != []} class="mt-3 flex flex-wrap gap-2">
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end

  defp alert_tone_class("info"), do: "bg-brand-soft text-brand-ink ring-brand-ink/30"
  defp alert_tone_class("success"), do: "bg-success-soft text-success-ink ring-success-ink/30"
  defp alert_tone_class("warning"), do: "bg-warning-soft text-warning-ink ring-warning-ink/30"
  defp alert_tone_class("danger"), do: "bg-danger-soft text-danger-ink ring-danger-ink/30"

  defp alert_icon("info"), do: "hero-information-circle-mini"
  defp alert_icon("success"), do: "hero-check-circle-mini"
  defp alert_icon("warning"), do: "hero-exclamation-triangle-mini"
  defp alert_icon("danger"), do: "hero-exclamation-circle-mini"

  @doc """
  Renders an inline live-announced status toast pill.
  """
  attr :id, :string, default: nil
  attr :tone, :string, default: "hero", values: ~w(hero warning success)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def status_toast(assigns) do
    ~H"""
    <div
      id={@id}
      role="status"
      aria-live="polite"
      class={[
        "forka-pop inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-bold shadow-3 dark:shadow-none",
        status_toast_tone_class(@tone),
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp status_toast_tone_class("hero"), do: "bg-hero text-hero-ink"

  defp status_toast_tone_class("warning"),
    do: "bg-warning-soft text-warning-ink ring-1 ring-warning-ink/30"

  defp status_toast_tone_class("success"),
    do: "bg-success-soft text-success-ink ring-1 ring-success-ink/30"

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-8 space-y-6 bg-transparent">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a tactile button or link styled with Forka tokens.

  ## Examples

      <.button>Send!</.button>
      <.button variant="secondary" phx-click="go">Cancel</.button>
      <.button navigate={~p"/rooms/new"}>Nova sala</.button>
  """
  attr :type, :string, default: nil

  attr :variant, :string,
    default: "primary",
    values: ~w(primary secondary link danger danger-link ghost)

  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :full, :boolean, default: false
  attr :class, :string, default: nil
  attr :navigate, :any, default: nil
  attr :patch, :any, default: nil
  attr :href, :any, default: nil
  attr :method, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <%= if @navigate || @patch || @href do %>
      <.link
        navigate={@navigate}
        patch={@patch}
        href={@href}
        method={@method}
        class={button_classes(@variant, @size, @full, @class)}
        {@rest}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        type={@type}
        class={button_classes(@variant, @size, @full, @class)}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  defp button_classes(variant, size, full, extra_class) do
    [
      "phx-submit-loading:opacity-75 inline-flex items-center justify-center gap-2 rounded-md transition",
      "disabled:bg-sunken disabled:text-ink-subtle disabled:ring-2 disabled:ring-inset disabled:ring-line disabled:shadow-none disabled:cursor-not-allowed disabled:active:translate-y-0",
      button_variant_class(variant),
      button_size_class(variant, size),
      full && "w-full",
      extra_class
    ]
  end

  defp button_variant_class("primary") do
    "bg-brand text-on-brand font-display font-bold shadow-lip-brand ring-1 ring-inset ring-brand-lip hover:bg-brand-strong active:translate-y-1 active:shadow-none"
  end

  defp button_variant_class("secondary") do
    "bg-surface text-ink font-display font-bold ring-2 ring-inset ring-line-strong shadow-lip-secondary hover:bg-canvas active:translate-y-1 active:shadow-none"
  end

  defp button_variant_class("danger") do
    "bg-danger text-on-danger font-display font-bold shadow-lip-danger hover:bg-danger-strong active:translate-y-1 active:shadow-none"
  end

  defp button_variant_class("link") do
    "bg-transparent text-brand-ink font-semibold underline underline-offset-4 hover:text-ink"
  end

  defp button_variant_class("danger-link") do
    "bg-transparent text-danger-ink font-semibold underline underline-offset-4 hover:text-ink"
  end

  defp button_variant_class("ghost") do
    "bg-transparent text-ink-muted font-semibold hover:bg-sunken hover:text-ink"
  end

  defp button_size_class(variant, _size) when variant in ["link", "danger-link"],
    do: "min-h-11 px-2 text-sm"

  defp button_size_class(_variant, "sm"), do: "min-h-11 px-3 text-sm"
  defp button_size_class(_variant, "md"), do: "min-h-11 px-4 text-base"
  defp button_size_class(_variant, "lg"), do: "min-h-12 px-6 text-lg"

  @doc """
  Renders a 44x44px icon button or link with a required accessible label.
  """
  attr :icon, :string, required: true
  attr :aria_label, :string, required: true
  attr :type, :string, default: "button"
  attr :navigate, :any, default: nil
  attr :patch, :any, default: nil
  attr :href, :any, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  def icon_button(assigns) do
    ~H"""
    <%= if @navigate || @patch || @href do %>
      <.link
        navigate={@navigate}
        patch={@patch}
        href={@href}
        aria-label={@aria_label}
        class={[
          "inline-flex size-11 items-center justify-center rounded-md text-ink-muted transition-colors",
          "hover:bg-sunken hover:text-ink",
          @class
        ]}
        {@rest}
      >
        <.icon name={@icon} class="size-5" />
      </.link>
    <% else %>
      <button
        type={@type}
        aria-label={@aria_label}
        class={[
          "inline-flex size-11 items-center justify-center rounded-md text-ink-muted transition-colors",
          "hover:bg-sunken hover:text-ink disabled:cursor-not-allowed disabled:opacity-50",
          @class
        ]}
        {@rest}
      >
        <.icon name={@icon} class="size-5" />
      </button>
    <% end %>
    """
  end

  @doc """
  Renders an input with label, optional helper hint, and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex min-h-11 items-center gap-3 text-sm font-semibold text-ink">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            "size-6 rounded-sm bg-sunken accent-brand focus:ring-0",
            @errors == [] && "border-line-strong",
            @errors != [] && "border-danger"
          ]}
          {@rest}
        />
        <span>{@label}</span>
      </label>
      <div class="mt-1 min-h-6">
        <.error :for={msg <- @errors}>{msg}</.error>
        <p :if={@hint && @errors == []} class="text-xs text-ink-subtle">{@hint}</p>
      </div>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={[
          "mt-2 block min-h-12 w-full rounded-md bg-sunken px-3 py-2 text-ink ring-2 ring-inset focus:outline-none sm:text-sm",
          @errors == [] && "ring-line-strong focus:ring-brand-ink",
          @errors != [] && "ring-danger focus:ring-danger"
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <div class="mt-1 min-h-6">
        <.error :for={msg <- @errors}>{msg}</.error>
        <p :if={@hint && @errors == []} class="text-xs text-ink-subtle">{@hint}</p>
      </div>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block min-h-24 w-full rounded-md bg-sunken px-3 py-2 text-ink placeholder:text-ink-subtle ring-2 ring-inset focus:outline-none sm:text-sm sm:leading-6",
          @errors == [] && "ring-line-strong focus:ring-brand-ink",
          @errors != [] && "ring-danger focus:ring-danger"
        ]}
        {@rest}
      >{Form.normalize_value("textarea", @value)}</textarea>
      <div class="mt-1 min-h-6">
        <.error :for={msg <- @errors}>{msg}</.error>
        <p :if={@hint && @errors == []} class="text-xs text-ink-subtle">{@hint}</p>
      </div>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          "form-input mt-2 block min-h-12 w-full rounded-md border-0 bg-sunken px-3 py-2 text-ink placeholder:text-ink-subtle ring-2 ring-inset focus:ring-2 focus:ring-inset focus:outline-none sm:text-sm sm:leading-6",
          @errors == [] && "ring-line-strong focus:ring-brand-ink",
          @errors != [] && "ring-danger focus:ring-danger"
        ]}
        {@rest}
      />
      <div class="mt-1 min-h-6">
        <.error :for={msg <- @errors}>{msg}</.error>
        <p :if={@hint && @errors == []} class="text-xs text-ink-subtle">{@hint}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-bold leading-6 text-ink">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="flex items-center gap-2 text-sm leading-6 text-danger-ink">
      <.icon name="hero-exclamation-circle-mini" class="size-4 shrink-0" />
      <span>{render_slot(@inner_block)}</span>
    </p>
    """
  end

  @doc """
  Renders an accessible tactile toggle switch.
  """
  attr :id, :string, required: true
  attr :checked, :boolean, default: false
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def switch(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4", @class]}>
      <div class="min-w-0">
        <span id={"#{@id}-label"} class="block text-sm font-bold text-ink">{@label}</span>
        <span :if={@description} class="block text-xs text-ink-subtle">{@description}</span>
      </div>
      <button
        id={@id}
        type="button"
        role="switch"
        aria-checked={to_string(@checked)}
        aria-labelledby={"#{@id}-label"}
        disabled={@disabled}
        class={[
          "relative inline-flex h-8 w-14 shrink-0 cursor-pointer items-center rounded-full p-1 transition-colors",
          if(@checked, do: "bg-success-700", else: "bg-line-strong"),
          @disabled && "cursor-not-allowed opacity-50"
        ]}
        {@rest}
      >
        <span
          aria-hidden="true"
          class={[
            "inline-block size-6 rounded-full bg-white shadow-1 transition-transform",
            @checked && "translate-x-6"
          ]}
        />
      </button>
    </div>
    """
  end

  @doc """
  Renders a segmented radiogroup control.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :on_select, :string, default: nil
  attr :cols, :integer, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def segmented_control(assigns) do
    has_selected? =
      Enum.any?(assigns.options, fn {opt_value, _} -> opt_value == assigns.value end)

    assigns = assign(assigns, :has_selected?, has_selected?)

    ~H"""
    <div
      id={@id}
      role="radiogroup"
      aria-label={@label}
      phx-hook="SegmentedControl"
      class={[
        "grid gap-1 rounded-md bg-sunken p-1 ring-1 ring-line",
        segmented_cols_class(@cols),
        @class
      ]}
      {@rest}
    >
      <button
        :for={{{opt_value, opt_label}, idx} <- Enum.with_index(@options)}
        type="button"
        role="radio"
        aria-checked={to_string(@value == opt_value)}
        tabindex={if(@value == opt_value or (!@has_selected? and idx == 0), do: "0", else: "-1")}
        phx-click={@on_select}
        phx-value-value={opt_value}
        class={[
          "min-h-11 rounded-sm px-3 font-display text-sm font-bold transition",
          if(@value == opt_value,
            do: "bg-surface text-ink shadow-lip-tile ring-2 ring-inset ring-line-strong",
            else: "text-ink-muted hover:text-ink"
          )
        ]}
      >
        {opt_label}
      </button>
    </div>
    """
  end

  defp segmented_cols_class(2), do: "grid-cols-2"
  defp segmented_cols_class(3), do: "grid-cols-3"
  defp segmented_cols_class(4), do: "grid-cols-4"
  defp segmented_cols_class(5), do: "grid-cols-5"
  defp segmented_cols_class(6), do: "grid-cols-6"
  defp segmented_cols_class(_), do: "grid-flow-col auto-cols-fr"

  @doc """
  Renders a surface card.
  """
  attr :id, :string, default: nil
  attr :padding, :string, default: "md", values: ~w(sm md lg)
  attr :bordered, :boolean, default: false
  attr :class, :string, default: nil
  slot :badge
  slot :title
  slot :meta
  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <article
      id={@id}
      aria-labelledby={@id && @title != [] && "#{@id}-title"}
      class={[
        "rounded-lg bg-surface text-ink shadow-2 dark:shadow-none",
        @bordered && "ring-1 ring-line",
        card_padding(@padding),
        @class
      ]}
    >
      <div :if={@badge != [] || @meta != []} class="mb-3 flex items-center justify-between gap-2">
        <div>{render_slot(@badge)}</div>
        <div class="text-xs font-semibold text-ink-subtle">{render_slot(@meta)}</div>
      </div>
      <h2
        :if={@title != []}
        id={@id && "#{@id}-title"}
        class="font-display text-xl font-bold text-ink"
      >
        {render_slot(@title)}
      </h2>
      <div class={@title != [] && "mt-2"}>
        {render_slot(@inner_block)}
      </div>
      <div :if={@actions != []} class="mt-4 flex flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </article>
    """
  end

  defp card_padding("sm"), do: "p-4"
  defp card_padding("md"), do: "p-6"
  defp card_padding("lg"), do: "p-8"

  @doc """
  Renders a toggle filter chip with `aria-pressed`.
  """
  attr :pressed, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@pressed)}
      disabled={@disabled}
      class={[
        "inline-flex min-h-11 items-center gap-2 rounded-full px-4 text-sm font-extrabold transition-colors",
        if(@pressed,
          do: "bg-ink text-canvas",
          else: "bg-sunken text-ink-muted ring-1 ring-inset ring-line hover:text-ink"
        ),
        @disabled && "cursor-not-allowed opacity-50",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a soft status badge pill.
  """
  attr :tone, :string, default: "neutral", values: ~w(neutral brand accent success warning danger)
  attr :icon, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-extrabold",
      badge_tone_class(@tone),
      @class
    ]}>
      <.icon :if={@icon} name={@icon} class="size-4 shrink-0" />
      <span>{render_slot(@inner_block)}</span>
    </span>
    """
  end

  defp badge_tone_class("neutral"), do: "bg-sunken text-ink-muted ring-1 ring-inset ring-line"
  defp badge_tone_class("brand"), do: "bg-brand-soft text-brand-ink"
  defp badge_tone_class("accent"), do: "bg-accent-soft text-accent-ink"
  defp badge_tone_class("success"), do: "bg-success-soft text-success-ink"
  defp badge_tone_class("warning"), do: "bg-warning-soft text-warning-ink"
  defp badge_tone_class("danger"), do: "bg-danger-soft text-danger-ink"

  @doc """
  Renders a player avatar circle with initial and deterministic player colour (1..6).
  """
  attr :initial, :string, default: nil
  attr :name, :string, default: nil
  attr :player_index, :integer, default: 1
  attr :size, :string, default: "md", values: ~w(xs sm md lg)
  attr :eliminated, :boolean, default: false
  attr :class, :string, default: nil

  def avatar(assigns) do
    letter =
      cond do
        is_binary(assigns.initial) and assigns.initial != "" ->
          assigns.initial |> String.first() |> String.upcase()

        is_binary(assigns.name) and assigns.name != "" ->
          assigns.name |> String.first() |> String.upcase()

        true ->
          "?"
      end

    assigns = assign(assigns, :letter, letter)

    ~H"""
    <span
      aria-hidden="true"
      class={[
        "inline-flex shrink-0 items-center justify-center rounded-full font-display font-bold shadow-lip-avatar",
        avatar_size_class(@size),
        if(@eliminated,
          do: "bg-sunken text-ink-subtle ring-2 ring-inset ring-line shadow-none",
          else: ["text-on-player", avatar_color_class(@player_index)]
        ),
        @class
      ]}
    >
      {@letter}
    </span>
    """
  end

  defp avatar_size_class("xs"), do: "size-6 text-xs"
  defp avatar_size_class("sm"), do: "size-8 text-sm"
  defp avatar_size_class("md"), do: "size-11 text-base"
  defp avatar_size_class("lg"), do: "size-14 text-xl"

  defp avatar_color_class(1), do: "bg-player-1"
  defp avatar_color_class(2), do: "bg-player-2"
  defp avatar_color_class(3), do: "bg-player-3"
  defp avatar_color_class(4), do: "bg-player-4"
  defp avatar_color_class(5), do: "bg-player-5"
  defp avatar_color_class(6), do: "bg-player-6"
  defp avatar_color_class(n) when is_integer(n), do: avatar_color_class(rem(abs(n - 1), 6) + 1)
  defp avatar_color_class(_), do: "bg-player-1"

  @doc """
  Renders an empty state container.
  """
  attr :icon, :string, default: nil
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :illustration
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class={["rounded-lg border-2 border-dashed border-line p-8 text-center", @class]}>
      <div :if={@illustration != []} class="mb-4 flex justify-center">
        {render_slot(@illustration)}
      </div>
      <div
        :if={@illustration == [] && @icon}
        class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-sunken text-ink-muted"
      >
        <.icon name={@icon} class="size-6" />
      </div>
      <h2 class="font-display text-xl font-bold text-ink">{@title}</h2>
      <p :if={@inner_block != []} class="mx-auto mt-2 max-w-md text-sm text-ink-muted">
        {render_slot(@inner_block)}
      </p>
      <div :if={@action != []} class="mt-6 flex justify-center">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="font-display text-2xl font-bold leading-8 text-ink">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-ink-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="mt-8 w-160 sm:w-full">
        <thead class="text-left text-sm leading-6 text-ink-subtle">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-semibold">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-line border-t border-line text-sm leading-6 text-ink-muted"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-sunken">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-sunken sm:rounded-l-lg" />
                <span class={["relative", i == 0 && "font-semibold text-ink"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-semibold">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-sunken sm:rounded-r-lg" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-brand-ink hover:text-ink"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-12">
      <dl class="-my-4 divide-y divide-line">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none font-semibold text-ink-subtle">{item.title}</dt>
          <dd class="text-ink">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-12">
      <.link
        navigate={@navigate}
        class="inline-flex min-h-11 items-center gap-2 text-sm font-semibold leading-6 text-brand-ink hover:text-ink"
      >
        <.icon name="hero-arrow-left-solid" class="size-4" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in four styles – outline, solid, mini, and micro.
  By default, the outline style is used, but `-solid`, `-mini`, and `-micro`
  suffixes may be applied.
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(ForkaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ForkaWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Translates Backpex messages.
  """
  def translate_backpex({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
