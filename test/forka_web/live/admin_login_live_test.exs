defmodule ForkaWeb.AdminLoginLiveTest do
  use ForkaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/log_in")

      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_admin(insert(:admin))
        |> live(~p"/admin/log_in")
        |> follow_redirect(conn, "/admin")

      assert {:ok, _conn} = result
    end
  end

  describe "admin login" do
    test "redirects if admin login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      admin = insert(:admin, password: password)

      {:ok, lv, _html} = live(conn, ~p"/admin/log_in")

      form =
        form(lv, "#login_form",
          admin: %{email: admin.email, password: password, remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/admin"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/admin/log_in")

      form =
        form(lv, "#login_form",
          admin: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/admin/log_in"
    end
  end
end
