defmodule ForkaWeb.LayoutsTest do
  use ForkaWeb.ConnCase, async: false

  setup do
    previous = Application.fetch_env(:forka, :worktree)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:forka, :worktree, value)
        :error -> Application.delete_env(:forka, :worktree)
      end
    end)
  end

  test "the home page shows the configured worktree name and port", %{conn: conn} do
    Application.put_env(:forka, :worktree, %{name: "test-worktree", port: 4555})

    badge = conn |> home_document() |> LazyHTML.query("#worktree-badge")

    assert LazyHTML.text(badge) =~ "test-worktree"
    assert LazyHTML.text(badge) =~ ":4555"
  end

  test "the home page omits the badge without worktree configuration", %{conn: conn} do
    Application.delete_env(:forka, :worktree)

    assert Enum.empty?(LazyHTML.query(home_document(conn), "#worktree-badge"))
  end

  defp home_document(conn) do
    conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
  end
end
