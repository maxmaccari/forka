defmodule ForkaWeb.PageControllerTest do
  use ForkaWeb.ConnCase

  test "GET / renders Forka welcome page in pt-BR for guests without Phoenix placeholder", %{
    conn: conn
  } do
    html = conn |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)

    refute html =~ "Phoenix Framework"
    refute html =~ "Peace of mind from prototype to production"
    assert Enum.count(LazyHTML.query(doc, "main #home-welcome-card")) == 1
    assert LazyHTML.text(LazyHTML.query(doc, "main h1")) =~ "Bora jogar Forka!"
    assert Enum.count(LazyHTML.query(doc, ~s|main a[href="#{~p"/players/register"}"]|)) == 1
    assert Enum.count(LazyHTML.query(doc, ~s|main a[href="#{~p"/players/log_in"}"]|)) == 1
  end

  test "GET / greets signed-in player and links to account settings", %{conn: conn} do
    player = insert(:player)
    html = conn |> log_in_player(player) |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)

    refute html =~ "Phoenix Framework"
    assert LazyHTML.text(LazyHTML.query(doc, "main h1")) =~ player.username
    assert Enum.count(LazyHTML.query(doc, ~s|main a[href="#{~p"/players/settings"}"]|)) == 1
  end
end
