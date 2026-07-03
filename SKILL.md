---
name: codespace-codex-handoff
description: Set up a local repository for GitHub Codespaces plus Tailscale SSH plus Codex Desktop/Mobile remote handoff. Use when the user wants a project-specific cloud Codespace that can be reached from Codex on Mac/iPhone, wants local-to-remote Codex handoff like the Guinness Chen X post, wants GitHub repo creation/linking for a local project, or wants startup automation for tailscaled and Codex app-server in a Codespace.
---

# Codespace Codex Handoff

## Core Workflow

Use this skill to turn a local project into a Codex-reachable Codespace:

1. Confirm the target local repo path and GitHub repo name.
2. Run `scripts/setup_codespace_handoff.sh` from this skill.
3. If the user explicitly asks for JetBrains/IntelliJ verification, use `computer-use` to open IntelliJ IDEA and confirm Git can fetch/push against the configured remote.
4. Add or refresh the Codex Desktop SSH remote project at the Codespace path.
5. Verify with:
   - direct SSH to the Tailscale IP or alias
   - `codex login status` on the Codespace
   - `codex app-server daemon version`
   - `codex_app.list_projects`
   - one remote smoke thread in `/workspaces/<RepoName>`
   - one worktree-backed local-to-remote handoff smoke test when requested

Read `references/operational-notes.md` before explaining master-branch handoff behavior, phone password behavior, duplicate projects, or auth caveats.

## Single-Command Setup

Run the script with explicit project values:

```bash
./scripts/setup_codespace_handoff.sh \
  --repo-dir /absolute/path/to/project \
  --github-repo OWNER/REPO \
  --visibility private \
  --codespace-name repo-codex-tailscale \
  --ssh-alias repo-codespace-tailscale
```

For fully automatic Tailscale login on first Codespace boot, set `TAILSCALE_AUTHKEY` in the shell before running the script. The script stores it as a GitHub Codespaces secret and never writes it to Git:

```bash
export TAILSCALE_AUTHKEY='<tailscale-auth-key>'
```

If `TAILSCALE_AUTHKEY` is absent, the script still installs startup automation, but the first Tailscale login may require a manual `tailscale up --ssh --hostname=<name>` or a later secret.

## Codex Login Boundary

The script installs and starts Codex in the Codespace, but ChatGPT login may still require user device auth:

```bash
codex login --device-auth
```

If the remote prints a device URL/code, present it to the user and wait. After they say done, verify:

```bash
codex login status
codex app-server daemon version
```

Do not claim the system is complete until remote Codex login and daemon status are verified.

## IntelliJ IDEA Link

GitHub linking is primarily Git remote configuration. IntelliJ usually picks it up automatically from `.git/config`.

If the user specifically wants IntelliJ linked:

1. Use `computer-use` for IntelliJ IDEA.
2. Open the project folder.
3. Open Git remotes/settings or the Git tool window.
4. Confirm the remote URL matches the script output.
5. Run fetch from IntelliJ.
6. If the user wants proof, create no code changes; just show that branch/remote status is clean or fetch succeeds.

Do not use IntelliJ to create hidden state that differs from command-line Git. CLI Git remains the source of truth.

## Handoff Rule

For X-post-style handoff, create/move Codex worktree-backed threads. Direct `master` checkout handoff can fail because Git does not allow the same branch checked out in two worktrees at once.

Use the final Codespace project path:

```text
/workspaces/<RepoName>
```

Avoid adding a second saved remote project for local-looking symlinks like `/Users/<name>/Documents/<RepoName>` unless the user explicitly asks; duplicates confuse Codex Desktop/Mobile.
