# Forka

Install Node.js with npm on PATH before building assets.

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

### Environment variables

Dotenvy loads `.env`, `.env.<env>`, `.env.local`, and `.env.<env>.local` in that
order. Test runs skip `.env.local`. Shell environment variables take precedence.
Keep shared defaults in the tracked files and personal values in the ignored
`.local` files. Read settings in `config/runtime.exs` with `env!/2,3`.

### Git worktrees

In development, the main checkout defaults to port 4000. A linked worktree
gets a default between 4100 and 4999 based on its path and shows its name and
port in the lower-left corner. Worktrees can pick the same default. If the
port is busy, set `PORT` to an available port, for example
`PORT=4555 iex -S mix phx.server`. In IEx, `o` opens the app and `m` opens the
development mailbox using the active port.

When HTTP tests enable the endpoint, the OS assigns an available port. Read
that port with `ForkaWeb.Endpoint.server_info(:http)`.

### Code checks

Run `mix precommit` with PostgreSQL running. It compiles with warnings treated
as errors, formats the code, runs Credo, Sobelow, MixAudit, Doctor, and Dialyzer,
then runs the tests with ExCoveralls. The first Dialyzer run builds a local PLT.

GitHub Actions runs parallel checks (**Test**, **Lint**, **Security**, **Doctor**,
**Dialyzer**, **Assets**, and **Audit**) on pull requests and pushes to `main`.
Merging to `main` requires a pull request and all checks except **Audit** to
pass (enforced by the `main` branch ruleset). Pull requests labelled only
`documentation` (and docs-only pushes to `main`) skip CI.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

The production endpoint uses `X-Forwarded-Proto` for HTTPS redirects and HSTS.
Run it behind a trusted TLS-terminating proxy that sets this header from the
original connection. Restrict access to the Phoenix listener to that proxy.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
