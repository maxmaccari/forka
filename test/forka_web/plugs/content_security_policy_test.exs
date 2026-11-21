defmodule ForkaWeb.Plugs.ContentSecurityPolicyTest do
  use ForkaWeb.ConnCase, async: true

  alias ForkaWeb.Plugs.ContentSecurityPolicy

  test "sets a fresh nonce in the policy on every request" do
    first = ContentSecurityPolicy.call(build_conn(), [])
    second = ContentSecurityPolicy.call(build_conn(), [])

    nonce = first.assigns.csp_nonce
    assert {:ok, <<_::144>>} = Base.decode64(nonce)
    assert second.assigns.csp_nonce != nonce

    assert [policy] = get_resp_header(first, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "script-src 'self' 'nonce-#{nonce}'"
    assert policy =~ "object-src 'none'"
  end

  test "the home page uses the response nonce for its scripts", %{conn: conn} do
    conn = get(conn, ~p"/")
    nonce = conn.assigns.csp_nonce
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "'nonce-#{nonce}'"

    assert [^nonce] = document |> LazyHTML.query("script[src]") |> LazyHTML.attribute("nonce")
    assert Enum.empty?(LazyHTML.query(document, ~s|script:not([src]):not([nonce="#{nonce}"])|))
  end
end
