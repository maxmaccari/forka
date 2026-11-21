# Security Directives: Rust

Read on demand, not always-on. It applies to Rust code in the app (a Rustler NIF under `native/`) and to Rust services and tools built with the same practices. The general rules (access control, secrets, LLM tools, dependencies) are in `.agents/rules/security.md`; this file adds what is specific to Rust. Section numbers are `R1`–`R10`.

## Quick rules

1. No `unsafe` unless a reviewed module needs it, and every `unsafe` block has a `// SAFETY:` comment (R2).
2. A panic is a denial of service: no `unwrap`, `expect` or indexing on input (R3).
3. Bound every input: body size, collection length, recursion depth, time (R4).
4. Secrets are `secrecy::SecretString` and are zeroized; they never reach `Debug`, logs or errors (R6).
5. `cargo audit` and `cargo deny check` pass in CI; a new crate is a one-way door (R9).

## R1. Threat model

Safe Rust removes memory corruption, not logic flaws. What still goes wrong: `unsafe` and FFI that break the invariants the compiler trusts, panics and unbounded allocation triggered by input (DoS), integer overflow in release builds, SQL and command injection through strings, secrets that leak through `Debug`, and the crate supply chain (`build.rs` and proc macros run on your machine at build time).

## R2. `unsafe` and FFI

- Put `#![forbid(unsafe_code)]` at the crate root of every crate that doesn't need it. Where it is needed, isolate it in one small module with a safe API, and use `#![deny(unsafe_op_in_unsafe_fn)]` and `clippy::undocumented_unsafe_blocks`.
- Every `unsafe` block states the invariant it relies on in a `// SAFETY:` comment, and has tests run under Miri (`cargo +nightly miri test`).
- FFI: check every pointer for null and every length before building a slice; never let a panic cross an `extern "C"` boundary (`catch_unwind`); own who frees each allocation.
- `cargo geiger` lists `unsafe` in dependencies; a dependency that adds a lot of it needs a reason.

## R3. Panics and errors

- Errors are values (`Result` with `thiserror` in libraries, `anyhow` at the edge). Deny `clippy::unwrap_used`, `clippy::expect_used`, `clippy::panic` and `clippy::indexing_slicing` in code that touches input; allow them in tests.
- Use `get()`, `checked_*`, `try_from` and `?` instead of `[]`, `as` and `unwrap`.
- Error messages for users don't carry internal paths, queries or secrets; the detail goes to the log with the cause chain.

## R4. Input and resource limits

- Parse, don't validate: turn input into types that can only hold valid values (newtypes with a fallible constructor) at the boundary.
- **Integer overflow wraps silently in release.** Use `checked_`/`saturating_` arithmetic for sizes, money and counters from input, or set `overflow-checks = true` in `[profile.release]`. Deny `clippy::arithmetic_side_effects` and `clippy::cast_possible_truncation` where sizes come from input.
- Cap allocation by input: no `Vec::with_capacity(n)` with an `n` from the wire; limit body size (`axum::extract::DefaultBodyLimit`, `tower_http::limit`), JSON depth, and string and collection lengths.
- `serde`: `#[serde(deny_unknown_fields)]` on request types; avoid untagged enums on large untrusted input.
- Every network call and handler has a timeout (`tower::timeout`, `tokio::time::timeout`). Regex comes from the `regex` crate (linear time); never compile a pattern from input without a size limit.
- Paths: never join input into a path; canonicalize and check it stays under the base directory.
- Commands: `std::process::Command::new(program).arg(x)`, never `sh -c` with interpolated input.

## R5. Data access and web services

- SQL through `sqlx::query!`/`query_as!` (checked at compile time) or bound parameters; never `format!` into SQL. Same access rules as `security.md` S2 and S5: every query is scoped by the caller's identity and tenant.
- axum/actix: authentication as a middleware or extractor that every protected route requires; authorization in the domain function, not in the handler alone.
- Cookies are `Secure`, `HttpOnly`, `SameSite=Lax`; CSRF protection for cookie-authenticated forms; CORS with an explicit origin list.
- Logging with `tracing`: structured, with no secrets or tokens in fields; add `#[instrument(skip(password, token))]`.

## R6. Secrets and cryptography

- Wrap secrets in `secrecy::SecretString`/`SecretBox` so `Debug` prints `[REDACTED]` and memory is zeroized on drop (`zeroize`). Never `#[derive(Debug)]` on a struct that holds a raw secret.
- Configuration from the environment or a secret store, never in the binary or the repo.
- Don't write crypto. Use RustCrypto or `ring`/`aws-lc-rs` through high-level APIs: `argon2` for passwords, `rustls` for TLS, `subtle::ConstantTimeEq` to compare MACs and tokens, `rand::rngs::OsRng` (or `getrandom`) for keys and tokens.
- TLS certificate verification stays on (`rustls` with `webpki-roots` or the platform verifier).

## R7. Rustler NIFs

- A NIF that panics is caught by Rustler and turned into an error, but a NIF that crashes the process (UB in `unsafe`, abort) takes the whole BEAM node down. Keep NIF code safe Rust.
- A NIF must return in about 1 ms; longer work runs on a dirty scheduler (`#[rustler::nif(schedule = "DirtyCpu")]`) or in a thread that sends a message back.
- Bound the input a NIF accepts (binary size, list length) in Elixir before the call, and decode terms with Rustler's typed decoders, never by trusting the shape.
- Don't create atoms from input inside a NIF (same atom-table rule as `security.md` S4).
- Precompiled NIFs (`rustler_precompiled`) are verified by checksum; keep the checksum file committed.

## R8. Concurrency

- `Send`/`Sync` hold only for safe code: a manual `unsafe impl Send` needs the same review as any `unsafe`.
- Bound channels and task spawning by input; an unbounded `mpsc` or `tokio::spawn` per request is a memory DoS.
- Don't hold a `std::sync::Mutex` guard across `.await`; use `tokio::sync::Mutex` or restructure.

## R9. Dependencies and supply chain

- `Cargo.lock` is committed for binaries and NIFs; CI builds with `--locked`.
- **cargo-audit** (`cargo audit`) checks `Cargo.lock` against the RustSec Advisory Database; run it in CI and on a schedule.
- **cargo-deny** (`cargo deny check`) in CI with a `deny.toml` that covers: `[advisories]` (RustSec, yanked crates denied), `[licenses]` (an allow list), `[bans]` (duplicate versions warned, known-bad crates denied), `[sources]` (only crates.io and listed git repos).
- **A new crate is a one-way door:** check it exists under that exact name on crates.io (typosquats), its downloads, owners, last release, `unsafe` use and `build.rs`. Prefer fewer, well-known crates; turn off default features you don't use.
- Optional for higher assurance: `cargo vet` (audits shared by trusted organizations) and `cargo auditable` (embeds the dependency list in the binary so scanners can check it later).
- GitHub Dependabot and `osv-scanner` read `Cargo.lock` too (`security.md` S12).

## R10. Tooling and checklist

CI runs, and a review checks they pass: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` (with the lints above), `cargo test`, `cargo audit`, `cargo deny check`; Miri for crates with `unsafe`; `cargo fuzz` targets for parsers of untrusted formats.

| Area | Check |
|---|---|
| `unsafe` | Forbidden, or isolated with `// SAFETY:` comments and Miri tests |
| Panics | No `unwrap`/`expect`/indexing on input outside tests |
| Limits | Body, length, depth, time and channel bounds on every input path |
| Arithmetic | Checked or saturating on sizes and money; release overflow checks considered |
| Injection | `sqlx` macros or bound params; `Command` with args, no shell |
| Secrets | `secrecy` + `zeroize`; nothing secret in `Debug`, logs or errors |
| Crypto | Library primitives only; constant-time compares; `OsRng` |
| NIF | Safe Rust, dirty scheduler for long work, bounded input, no atoms from input |
| Deps | `cargo audit` and `cargo deny` clean; new crates checked |

**Sources:** ANSSI Secure Rust Guidelines (anssi-fr.github.io/rust-guide), RustSec Advisory Database (rustsec.org), cargo-deny (embarkstudios.github.io/cargo-deny), Rust Secure Code WG (github.com/rust-secure-code/wg), The Rustonomicon (doc.rust-lang.org/nomicon), Clippy lints (rust-lang.github.io/rust-clippy), Rustler (github.com/rusterlium/rustler), OWASP ASVS 5.0 and Cheat Sheets for the web parts.
