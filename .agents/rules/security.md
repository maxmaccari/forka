---
trigger: always_on
description: Secure coding directives for any Phoenix LiveView app (Elixir, Ecto, HEEx, LiveView, JS hooks, LLM features, dependencies, deployment), S1–S14, with the review checklist
---

# Security Directives: Phoenix LiveView

Read these before you write or review code that handles a user, a request, a file, a secret, a dependency, or a model's output. They are as binding as `AGENTS.md` and extend its "Code Review Rules → Security". They follow OWASP ASVS 5.0 level 1 as the floor and the EEF Security Working Group's guides for the BEAM. Rust code (a Rustler NIF or a Rust service) also follows `.agents/shared/security-rust.md`. Sources are in S14.

## Quick rules

1. Every user action runs on a `%Scope{}` and the Context decides; the LiveView never decides access (S2).
2. Treat everything from the browser as forged: params, `phx-value-*`, hidden inputs, hook payloads, uploads, the URL (S3).
3. Never create atoms, modules or code from input; never `binary_to_term` untrusted data (S4).
4. Ecto queries take values with `^`, never by string building; `cast/3` lists only fields the user may set (S5).
5. HEEx escapes; `raw/1` only on content you produced or sanitized (S6).
6. Secrets live in `config/runtime.exs` from the environment and never reach logs, assigns, broadcasts, job args or prompts (S8).
7. Model output is untrusted input, and tools a model calls get the user's scope, never more (S11).
8. A new dependency is a security decision: check it exists, is maintained and is clean in `mix deps.audit` and `mix hex.audit` (S12).

## S1. Threat model in one paragraph

A LiveView app keeps state on the server, so the main risks are not in the browser but in what the server trusts: a socket event that skips the check the page did on mount, a query not scoped to the tenant, an atom or term built from input, a secret that leaks through `inspect`, and an LLM tool that does more than the user may. Map each feature to the OWASP Top 10:2025: broken access control (A01), security misconfiguration (A02), software supply chain failures (A03), cryptographic failures (A04), injection (A05), insecure design (A06), authentication failures (A07), integrity failures (A08), logging and alerting failures (A09), mishandling of exceptional conditions (A10). A spec that adds a login, a role, an upload, a payment, a webhook, an outbound call or a model tool names its threats in §4 as a one-way door.

## S2. Authentication and access control

- **Use `mix phx.gen.auth`.** Don't write password hashing, session tokens or magic links by hand. Keep its defaults (session renewal on login, tokens deleted on logout and password change) and prefer `--hashing-lib argon2` when the host has the memory; bcrypt is the minimum.
- **Every LiveView sits in a `live_session` whose `on_mount` hook matches its audience.** Protected pages use `{ForkaWeb.UserAuth, :require_authenticated}` (or stricter, such as an admin hook); public pages (log in, registration, landing) use `:mount_current_scope`, which loads the scope without requiring one. A protected route in a public `live_session` or pipeline is a blocker; a public page is fine where the generator puts it. `live_redirect`/`navigate` between sessions forces a new mount, so access is checked again.
- **Authorize every `handle_event`, `handle_info` and `handle_params` that reads or changes data**, not only `mount`. The socket stays open for hours and events are forged as easily as HTTP requests. The Context function takes `socket.assigns.current_scope` and returns `{:error, :unauthorized}` or `{:error, :not_found}`.
- **Scope every query by the scope** (`where: r.user_id == ^scope.user.id`, or the org/tenant id). Loading by id alone is an IDOR. Return `:not_found` for "exists but not yours", so ids can't be probed.
- **Permission is a domain rule with a test for the wrong scope**: another user, another tenant, a removed member, a lower role.
- **Revocation reaches open sockets.** On logout, password change, role change or ban, broadcast a disconnect (`ForkaWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})`), as the generated `log_out_user` does.
- **Re-authenticate (sudo mode) before sensitive changes:** email, password, 2FA, deleting the account, payout details. `phx.gen.auth` ships sudo mode (`require_sudo_mode`).
- **Rate-limit authentication**: login, magic link, password reset, sign-up, and any endpoint that sends email or costs money (Hammer or PlugAttack, keyed by IP and by account). Give the same answer and timing for "no such user" and "wrong password".
- **Never decide access in the template or in JS.** Hiding a button is presentation; the Context still refuses.

## S3. Input from the browser

- Params, `phx-value-*`, form fields (hidden ones too), `pushEvent` payloads from hooks, `handle_params` URLs and uploaded files are attacker-controlled. Cast and validate them at the Context boundary with a changeset or a typed function head before use.
- **Ids from the client are claims, not facts.** Reload the record through the scoped Context; never trust an id or a price that came in an event.
- **Bound everything**: string length (`validate_length`), list size, pagination `limit` (cap it server-side), numeric ranges, the websocket `max_frame_size`, and the LiveView upload limits (S7).
- **Redirects:** `redirect(to: path)` only takes local paths; never pass user input to `redirect(external: ...)` or a `return_to` without checking it against an allowlist (open redirect).
- **Regex on input** runs with a size limit, or use `String` functions; a backtracking pattern on a long string is a denial of service.
- **CSRF:** keep `protect_from_forgery` in `:browser` and the `_csrf_token` in the LiveSocket params. Never move a state-changing action to a `GET`.
- **Origin check:** leave `check_origin` on in prod (`config/runtime.exs` sets the host). Never set it to `false`.

## S4. BEAM-specific dangers

- **Atoms are never garbage collected.** Never `String.to_atom/1`, `List.to_atom/1`, `Module.concat/1` or `Jason.decode(keys: :atoms)` on input. Map strings to atoms with a function head or a whitelist (`Ecto.Enum`, `case`), or `String.to_existing_atom/1` inside a whitelist.
- **No code from data:** never `Code.eval_string`, `Code.eval_quoted`, `apply/3` or `Kernel.apply` with a module or function name taken from input.
- **`:erlang.binary_to_term/1` on untrusted data can create atoms and executable funs.** Use `Plug.Crypto.non_executable_binary_to_term(bin, [:safe])`, and only on data you signed (`Phoenix.Token`, `Plug.Crypto.sign`).
- **XML:** `:xmerl` creates atoms and resolves entities; don't parse untrusted XML with it.
- **Timing:** compare tokens, signatures and API keys with `Plug.Crypto.secure_compare/2`, never `==`.
- **Randomness:** `:crypto.strong_rand_bytes/1` for tokens, ids and nonces; never `:rand` or `Enum.random` for anything secret.
- **Boolean coercion:** `"false"` is truthy. Cast flags with a changeset (`:boolean`) instead of `if params["admin"]`.
- **Processes are a resource.** Don't spawn a process, open a PubSub topic, or start a timer per untrusted event without a bound. Supervise long work and give `Task.async` and calls a timeout.

## S5. Database (Ecto and SQL)

- Interpolate values with `^`. `fragment/1` takes only literals; values go as `?` with `^`. `Ecto.Adapters.SQL.query/3` takes parameters, never a built string. Dynamic columns or sort fields come from a whitelist (`String.to_existing_atom` after a `case`, or `Ecto.Enum`).
- **Mass assignment:** `cast/3` lists only the fields the user may set. Never cast `user_id`, `org_id`, `role`, `confirmed_at`, `price`, `status` from params; set them in the Context with `put_change` or `Ecto.build_assoc` from the scope.
- **Unique and foreign-key constraints** in the migration, with `unique_constraint`/`foreign_key_constraint` in the changeset; a check in Elixir alone races.
- **Multi-tenant data** (schema prefix or a tenant column) gets the tenant from the scope in every query, including `Repo.preload`, `Repo.aggregate`, and vector searches (S11).
- The app's database user owns only the app's schema; it is not a superuser. Migrations that drop or rewrite data on existing rows are one-way doors.

## S6. Output: HTML, JSON and the browser

- **HEEx escapes by default.** `Phoenix.HTML.raw/1` is allowed only on HTML you built from trusted parts or passed through a sanitizer (`HtmlSanitizeEx`, or `Earmark` output sanitized afterwards). User Markdown is rendered, then sanitized, never the other way round.
- **Attributes:** never put user input in `href`/`src` without checking the scheme (`http`, `https`, `mailto`); `javascript:` URLs run code. Never build `style` or event-handler attributes from input.
- **Inline scripts** carry `nonce={@csp_nonce}` and never interpolate user data; pass data through `data-*` attributes or `phx-hook` and read it as text.
- **Content Security Policy:** keep the nonce-based CSP plug from the baseline (`default-src 'self'`, `script-src 'self' 'nonce-…'`, `object-src 'none'`, `frame-ancestors 'self'`). Adding a host to it is reviewed like code, and `'unsafe-inline'` or `'unsafe-eval'` in `script-src` is a blocker.
- **Headers:** keep `put_secure_browser_headers`; in prod use `force_ssl` with HSTS (`config :forka, ForkaWeb.Endpoint, force_ssl: [hsts: true]`), secure, `HttpOnly`, `SameSite=Lax` session cookies, and a signing salt set in `runtime.exs`.
- **CORS:** only for an API that needs it, with an explicit origin list (never `*` with credentials), and never on the `:browser` pipeline.
- **Error pages** don't show stack traces, queries or ids in prod (`debug_errors: false`).
- **JSON APIs** return only the fields of a view module, never `Jason.encode!(struct)` of a schema (it would leak hashed passwords or internal fields).
- **Broadcasts and assigns** carry the read model for their audience only (`docs/architecture.md`). Anything in an assign reaches the browser's diff or memory: no secrets, no other users' data.

## S7. Files and uploads

- `allow_upload` sets `accept` (extensions and MIME), `max_entries` and `max_file_size`. The extension is a hint: check the magic bytes of what you keep, and re-encode images when you can.
- Store uploads outside `priv/static`, under a generated name (UUID), never the client's filename. Serve them through a controller that authorizes the scope, or through signed, expiring URLs.
- **Paths:** never join input into a path. When a name must map to a file, use `Path.safe_relative/2` and check the result stays inside the base directory.
- Archives (zip, tar) are bounded by file count, total size and path (zip slip). Parsing PDFs, images or office files runs in a supervised, time-limited process.

## S8. Secrets, configuration and logs

- **Secrets come from the environment in `config/runtime.exs`** (Dotenvy in dev), never in `config/*.exs`, the repo, the image, or a fixture. `.env` stays git-ignored. A committed secret is rotated, not just deleted.
- **Make rotation cheap:** one variable per secret, read in one place, with a documented rotation step.
- **Redact:** `@derive {Inspect, except: [:password, :token, ...]}` on schemas and structs with secrets; `config :phoenix, :filter_parameters` covers every secret param name (`password`, `token`, `secret`, `api_key`, `authorization`, `code`).
- **Logs** never carry a secret, a full token, a session cookie, or personal data you don't need. Log security events (login failure, permission denied, sudo mode, role change) with the actor and the target id, so an incident can be traced (A09).
- **Oban job args are stored in plain text** in the database: pass ids, never secrets or tokens, and reload the record and check permission inside `perform/1`.
- **Least privilege:** each external credential (API key, S3, SMTP, the database) has only the rights the app uses, one per environment.

## S9. Outbound calls and webhooks

- **SSRF:** a URL from a user or a model is fetched only after checking the scheme and host against an allowlist, or after resolving it and refusing private, loopback and link-local ranges. Turn off redirects (`Req` `redirect: false`) or recheck each hop.
- Every `Req` call has a `receive_timeout` and a size limit, and runs through a module (port) so tests can fake it.
- **Incoming webhooks** compute the expected signature over the raw request body (keep it with a `body_reader`) and compare it with the provider's header using `Plug.Crypto.secure_compare/2`. They also check the timestamp to refuse replays, and are idempotent by event id.
- TLS verification stays on; never pass `verify: :verify_none`.

## S10. Frontend JavaScript (hooks and assets)

- **Hooks are the only custom JS** (`AGENTS.md` §3). In a hook, write text with `textContent`, never `innerHTML`, `outerHTML`, `insertAdjacentHTML` or `document.write` with data from the DOM, the server or the URL. The same holds for ports in Elm and `{@html}` in Svelte.
- **Data reaches a hook as text** (`data-*`, `this.el.dataset`, `pushEvent` replies) and is parsed with `JSON.parse`, never `eval` or `new Function`.
- **Nothing secret in the bundle:** no API keys, no feature flags that grant access. `localStorage` holds no tokens; the session is the `HttpOnly` cookie.
- `window.open` and external links use `rel="noopener noreferrer"`. Third-party scripts are avoided; when one is needed it is pinned, served from `'self'` or with Subresource Integrity, and added to the CSP on purpose.
- **npm:** keep `package.json` small (Phoenix ships esbuild and Tailwind as binaries). Commit the lockfile, install with `npm ci`, review install scripts of new packages, and audit with `npm audit --omit=dev` or `osv-scanner`.

## S11. LLM features (prompts, tools, embeddings)

Follow the OWASP Top 10 for LLM Applications (2025). A model is an untrusted user who can be talked into anything.

- **Prompt injection is not solved by the prompt.** Anything the model reads (user text, a document, a web page, a tool result, a retrieved chunk) can carry instructions. The defence is what the model is allowed to do, not what it is told.
- **Tools run with the user's `%Scope{}`** and go through the same Context functions as the UI, with the same authorization and validation. A tool never takes a user or tenant id from the model's arguments; it reads it from the scope.
- **Least agency:** give each call the fewest tools it needs; tools that spend money, send messages, delete data or reach the network need a confirmation from the user or a hard limit.
- **Model output is input** (A05/LLM05): cast tool arguments with a changeset; render output as text or sanitized Markdown, never `raw/1`; never put it in SQL, a shell, a path, an atom, a URL to fetch (S9) or code.
- **No secrets in prompts.** Keys, other users' data and internal notes don't go into a system prompt; assume the system prompt leaks (LLM07).
- **Embeddings and RAG** (pgvector): store the tenant/user id with each vector and filter by the scope in the same query as the similarity search; a shared index leaks data across tenants (LLM08).
- **Unbounded consumption** (LLM10): cap tokens per call, calls per user per time window, tool-loop iterations and total cost; time out long calls.
- **Log prompts and tool calls** for audit with personal data redacted, and keep a way to turn a model feature off without a deploy.

## S12. Dependencies and supply chain

- `mix.lock` and `package-lock.json` are committed; CI installs from them (`mix deps.get --check-locked`, `npm ci`).
- `mix precommit` runs `sobelow --config` and `deps.audit`; audits and reviews also run `mix hex.audit` (retired packages). A vulnerable or retired package a change adds is a blocker.
- **A new package is a one-way door.** Before adding it, check it exists on hex.pm or npm under that exact name (models invent names and attackers register them), its downloads, owner, last release and open advisories. Prefer the standard library, Phoenix, Plug and Ecto.
- **Watch the databases:** the GitHub Advisory Database (Dependabot alerts and security updates on, for `mix`, `npm`, `cargo` and GitHub Actions), and OSV.dev (`osv-scanner scan source -r .` reads `mix.lock`, `package-lock.json` and `Cargo.lock` at once). The EEF CNA publishes CVEs for Erlang and Elixir packages.
- **GitHub Actions:** pin third-party actions by commit SHA, set `permissions:` to the minimum per workflow, never echo secrets, and don't run untrusted PR code with secrets (`pull_request_target`).
- **Sobelow skips** (`# sobelow_skip`) carry a comment that says why; a skip added by a change is reviewed like code.

## S13. Deployment and operations

- Run a release (`mix release`) as a non-root user, with `MIX_ENV=prod` and `PHX_SERVER=true`, and only the HTTP port public.
- **Erlang distribution:** a random `RELEASE_COOKIE` per environment from the secret store; never expose EPMD (4369) or the distribution ports to the internet; use TLS distribution when nodes cross a network you don't own. Anyone with the cookie runs any code.
- `LiveDashboard`, `/mailbox` and admin tools are behind authentication and an admin role in prod, or not routed at all.
- Database connections use TLS when the database is not on the same host; backups are encrypted and restored at least once to prove they work.
- Keep Erlang/OTP, Elixir and Phoenix on supported versions; apply security releases within days.
- Personal data: collect the minimum, define retention, and make deletion real (including uploads, embeddings and backups' expiry).
- Publish a `SECURITY.md` (the kit installs a template) and turn on GitHub private vulnerability reporting.

## S14. Review checklist and sources

`local-review` walks this list when the diff touches the area; `audit` grades it in Pillar 3.

| Area | Check |
|---|---|
| Access | New route in the right `live_session`/pipeline; every mutating event, `handle_params` and tool authorizes through a scoped Context; wrong-scope test exists |
| Input | Changesets cast and bound input; no ids, prices or roles trusted from the client; no `redirect(external:)` with input |
| BEAM | No `String.to_atom`, `Code.eval_*`, `binary_to_term` or dynamic `apply` on input; `secure_compare` for secrets |
| Ecto | Values with `^`; no programmatic fields in `cast/3`; tenant filter on every query |
| Output | No `raw/1` on untrusted content; URLs scheme-checked; CSP unchanged or the change justified |
| Files | Upload limits set; stored under generated names outside `priv/static`; served with authorization |
| Secrets | Only from `runtime.exs`; redacted in `Inspect`, logs, assigns, broadcasts, job args and prompts |
| Outbound | Allowlist or private-range block, timeouts, signature check on webhooks |
| JS | No HTML sinks with data; nothing secret in the bundle; lockfile updated with the change |
| LLM | Tools scoped and validated; output treated as input; limits on tokens, calls and loops |
| Deps | `deps.audit`, `hex.audit` and `sobelow` clean for what the change adds; new packages checked |

**Sources** (prefer them over memory; check the current version):
OWASP Top 10:2025 (owasp.org/Top10/2025), OWASP ASVS 5.0 (github.com/OWASP/ASVS), OWASP Cheat Sheet Series (cheatsheetseries.owasp.org), OWASP Top 10 for LLM Applications 2025 (genai.owasp.org), CWE Top 25 (cwe.mitre.org/top25), EEF Security WG guides (security.erlef.org: Secure Coding and Deployment Hardening, Web Application Security Best Practices for BEAM languages), Elixir Secure Coding Training (github.com/erlef/elixir-secure-coding), Phoenix security guide (hexdocs.pm/phoenix/security.html), Sobelow (github.com/nccgroup/sobelow), mix_audit (github.com/mirego/mix_audit), GitHub Advisory Database (github.com/advisories), OSV.dev.
