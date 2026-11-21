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

In development, the main checkout uses port 4000. Each linked worktree gets a
stable port from 4100 to 4999 based on its path and shows its name and port in
the lower-left corner. Set `PORT` to override it, for example
`PORT=4555 iex -S mix phx.server`. In IEx, `o` opens the app and `m` opens the
development mailbox using the active port.

### Code checks

Run `mix precommit` with PostgreSQL running. It compiles with warnings treated
as errors, formats the code, runs Credo, Sobelow, MixAudit, Doctor, and Dialyzer,
then runs the tests with ExCoveralls. The first Dialyzer run builds a local PLT.

GitHub Actions runs on pull requests and pushes to `main`. It verifies formatting
and the Mix lockfile, runs `mix precommit` against PostgreSQL, audits the npm
lockfile with `npm --prefix assets audit --audit-level=low`, and builds the assets.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

The production endpoint enforces HTTPS and HSTS. If a trusted reverse proxy
terminates TLS, configure `force_ssl` in `config/prod.exs` to use the scheme
forwarded by that proxy.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
