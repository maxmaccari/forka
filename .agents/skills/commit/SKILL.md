---
name: commit
description: >-
  Use when the user wants to commit Forka's pending changes (commit, commit
  --ask). Splits the working tree into a series of commits by layer, in
  dependency order, so the history reads as a story; messages are brief, with no prose.
  Commits a single-step change directly; shows the split and asks first when it has several
  commits, or with --ask. Never pushes.
---

# `commit` — Commit by Layer

You turn the pending changes into a short series of commits that show how the change was built. Anyone reading `git log` later should be able to follow the order without opening the diffs.

Shared rules (asking questions, safety, writing): `.agents/shared/conventions.md`.

---

## Usage

- `commit` — commit the pending changes. A single-step change is committed directly; a split with several commits is shown first.
- `commit --ask` — always show the split and wait for approval, even for a single commit.

---

## Rules

1. **Asking depends on the split** (conventions §8). Running `commit` is the user's go-ahead to commit. Ask first only when the split has several commits, or with `--ask`. Never push, amend, rebase, or skip hooks (`--no-verify`).
2. **One step per commit, in build order.** Each commit stands on the ones before it: nothing references code from a later commit, and tests go in the same commit as the code they test.
3. **Only the change.** Stage by path or by patch, never `git add -A` or `git add .`. Leave out `docs/tmp/`, crash dumps (`erl_crash.dump`), `.env*`, secrets, and editor or OS files, and say so.
4. **Don't change the code.** No formatting, fixes, or cleanups; commit what is there.
5. **Brief messages** (Step 4).

---

## Step 1: Read the Change

1. `git status --porcelain`, `git diff --stat`, and `git diff` (plus `git diff --cached` if something is staged). If something is already staged, ask whether to commit only that or the whole working tree.
2. **Branch:** if HEAD is the default branch, offer to move the changes to a new branch, `<type>/<short-kebab-topic>`, in a new worktree from `HEAD` (conventions §13). This checkout stays on the default branch, clean:

   ```bash
   git stash push --include-untracked -m "commit: <branch>"
   git worktree add -b <branch> <path> HEAD
   git -C <path> stash pop --index
   ```

   If a step fails, `git stash pop --index` here brings the changes back. From then on, commit in the worktree. If the user declines, commit here.
3. **Style:** `git log --oneline -15` for the repo's message style and scopes.

---

## Step 2: Find the Story

1. **Group bottom-up by layer:** deps and config → migrations → schemas → Contexts → OTP and jobs → web (router, LiveViews, components).
2. **Place the rest:**
   - Unrelated fixes and refactors the feature needs → their own commits, first.
   - A new spec (`docs/specs/`) → one commit before the code: the why. The spec's ticked slice and §8 As Built go with the last commit.
   - ADRs, `README.md`, domain docs, `docs/roadmap.md` → a last commit.
   - Unrelated changes the feature doesn't need → their own commit at the end, or left out if the user prefers.
3. **A file with hunks for two steps:** split it with a patch (Step 3). If the hunks can't be separated, the whole file goes in the later step; note it in the proposal.

Aim for 2–6 commits. More than that usually means steps that should be merged; one usually means the change is a single step, which is fine.

---

## Step 3: Propose & Commit

1. **Decide whether to ask.** Ask when `--ask` was given, or when the split has more than one commit (for example, after a build). Otherwise, skip the proposal (item 2) and go to item 3. In a pipeline run, never ask: show the split and commit it (conventions §12).
2. **When asking,** show the split and list the options:
   - **Commit** — make the commits as proposed.
   - **Squash to one commit** — the whole change in one commit, with one message.
   - **Edit** — change the grouping or the messages, then show it again.
   - **Cancel** — commit nothing.

   ```text
   1. feat(catalog): add products table and schema
      priv/repo/migrations/..._create_products.exs, lib/forka/catalog/product.ex, test/...
   2. feat(catalog): list and create products
      lib/forka/catalog.ex, test/forka/catalog_test.exs
   Left out: erl_crash.dump (crash dump)
   ```

3. For each commit, in order:
   - Stage its files with `git add <paths>`. For part of a file, save only its hunks from `git diff <file>` to a patch in a scratch folder and run `git apply --cached <patch>`.
   - Check `git diff --cached --stat` against the proposal, then `git commit -F -` with the message on stdin.
4. If a commit hook fails, stop, show the output, and leave the rest uncommitted.
5. Finish with `git status --short` (only what was left out on purpose remains) and `git log --oneline <base>..HEAD`.

---

## Step 4: Write the Messages

Brief and summarized; no prose. Follow the repo's style; with none, use Conventional Commits.

- **Subject:** `type(scope): summary` — imperative, lowercase, no period, at most 72 characters (aim for 50). Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. Scope: the Context or area (`catalog`, `web`, `deps`).
- **Body:** optional. At most three short bullets, only for what the subject can't carry: a non-obvious decision or a side effect. No paragraphs, no file lists, no "This commit...".
- **References:** If `docs/roadmap.md` exists and links the spec's roadmap item to issue #NN, add `Refs #NN` to the last commit.
- Keep any trailer your tool requires (e.g. `Co-Authored-By`).

```text
feat(catalog): list and create products

- price stored as integer cents
```

---

## Step 5: Hand Off

Show the new commits and the worktree's path if Step 1 created one (conventions §13). When the user asks for a PR, use the [`pull-request` skill](../pull-request/SKILL.md).
