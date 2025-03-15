defmodule ForkaWeb.RedirectController do
  use ForkaWeb, :controller

  def redirect_to_categories(conn, _params) do
    conn
    |> Phoenix.Controller.redirect(to: ~p"/admin/categories")
    |> Plug.Conn.halt()
  end
end
