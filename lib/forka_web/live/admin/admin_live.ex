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

  defp password_field(context) do
    {field, field_data} = context.field
    assigns = %{label: field_data.label, field: field}

    ~H"""
    <div>
      <div class=" flex flex-col items-stretch space-y-2 px-6 py-4 sm:flex-row sm:space-y-0 sm:py-3">
        <div class="sm:self-center hyphens-auto wrap-break-word pr-2 sm:w-1/4">
          <p class="text-content block wrap-break-word text-sm font-medium">
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
