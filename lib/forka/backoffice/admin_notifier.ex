defmodule Forka.Backoffice.AdminNotifier do
  @moduledoc "Delivers account confirmation, email change, and password reset emails to admins."

  import Swoosh.Email

  alias Forka.Backoffice.Admin
  alias Forka.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Forka", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  @spec deliver_confirmation_instructions(Admin.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_confirmation_instructions(admin, url) do
    deliver(admin.email, "Confirmation instructions", """

    ==============================

    Hi #{admin.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a admin password.
  """
  @spec deliver_reset_password_instructions(Admin.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reset_password_instructions(admin, url) do
    deliver(admin.email, "Reset password instructions", """

    ==============================

    Hi #{admin.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a admin email.
  """
  @spec deliver_update_email_instructions(Admin.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_update_email_instructions(admin, url) do
    deliver(admin.email, "Update email instructions", """

    ==============================

    Hi #{admin.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
