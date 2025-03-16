defmodule ForkaWeb.PlayerSessionController do
  use ForkaWeb, :controller

  alias Forka.Players
  alias ForkaWeb.PlayerAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:player_return_to, ~p"/players/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"player" => player_params}, info) do
    if player = get_player_by_params(player_params) do
      conn
      |> put_flash(:info, info)
      |> PlayerAuth.log_in_player(player, player_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_credentials_in_flash(player_params)
      |> redirect(to: ~p"/players/log_in")
    end
  end

  defp get_player_by_params(%{"email" => email, "password" => password}),
    do: Players.get_player_by_email_and_password(email, password)

  defp get_player_by_params(%{"email_or_username" => email_or_username, "password" => password}),
    do: Players.get_player_by_credentials(email_or_username, password)

  def put_credentials_in_flash(conn, %{"email" => email}),
    do: put_flash(conn, :email, String.slice(email, 0, 160))

  def put_credentials_in_flash(conn, %{"email_or_username" => email_or_password}),
    do: put_flash(conn, :email_or_password, String.slice(email_or_password, 0, 160))

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> PlayerAuth.log_out_player()
  end
end
