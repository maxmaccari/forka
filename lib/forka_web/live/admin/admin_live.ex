defmodule ForkaWeb.Admin.AdminLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Backoffice.Admin,
      repo: Forka.Repo,
      update_changeset: &Forka.Backoffice.Admin.email_changeset/3,
      create_changeset: &Forka.Backoffice.Admin.registration_changeset/3
    ],
    pubsub: [
      server: Forka.PubSub,
      topic: "words"
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {ForkaWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Admin"

  @impl Backpex.LiveResource
  def plural_name, do: "Admins"

  @impl Backpex.LiveResource
  def translate({"New %{resource}", _opts}), do: "Register admin"
  def translate({msg, opts}), do: Backpex.translate({msg, opts})

  @impl Backpex.LiveResource
  def fields do
    [
      email: %{
        module: Backpex.Fields.Text,
        label: "Email",
        searchable: true
      },
      password: %{
        module: Backpex.Fields.Text,
        label: "Password",
        only: [:new],
        render_form: &password_field/1
      }
    ]
  end

  defp password_field(assigns) do
    ~H"""
    <div>
      <Backpex.HTML.Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :center)}>
          <Backpex.HTML.Layout.input_label for={@form[@name]} text={@field_options[:label]} />
        </:label>
        <Backpex.HTML.Form.input
          type="password"
          field={@form[@name]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          readonly={@readonly}
        />
      </Backpex.HTML.Layout.field_container>
    </div>
    """
  end
end
