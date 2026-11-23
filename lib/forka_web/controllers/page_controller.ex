defmodule ForkaWeb.PageController do
  use ForkaWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:current_path, "/")
    |> render(:home)
  end
end
