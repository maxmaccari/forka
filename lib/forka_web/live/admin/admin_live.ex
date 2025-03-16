defmodule ForkaWeb.Admin.AdminLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Forka.Backoffice.Admin,
      repo: Forka.Repo,
      update_changeset: &Forka.Backoffice.Admin.email_changeset/3,
      create_changeset: &Forka.Backoffice.Admin.registration_changeset/3
    ],
    layout: {ForkaWeb.Layouts, :admin},
    pubsub: [
      name: Forka.PubSub,
      topic: "words",
      event_prefix: "word_"
    ]

  @impl Backpex.LiveResource
  def singular_name, do: "Admin"

  @impl Backpex.LiveResource
  def plural_name, do: "Admins"

  @impl Backpex.LiveResource
  def create_button_label, do: "Register admin"

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

  defp password_field(context) do
    {field, field_data} = context.field
    assigns = %{label: field_data.label, field: field}

    ~H"""
    <div>
      <div class=" flex flex-col items-stretch space-y-2 px-6 py-4 sm:flex-row sm:space-y-0 sm:py-3">
        <div class="sm:self-center hyphens-auto break-words pr-2 sm:w-1/4">
          <p class="text-content block break-words text-sm font-medium">
            {@label}
          </p>
        </div>

        <div class="w-full sm:w-3/4">
          <div class="">
            <div class="form-control">
              <input
                type="password"
                name={"change[#{@field}]"}
                id={"resource-form_#{@field}"}
                class="input input-bordered"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
