---
name: codespace-codex-handoff
description: Set up a local repository for GitHub Codespaces plus Tailscale SSH plus Claude Code plus Codex Desktop/Mobile remote handoff. Use when the user wants a project-specific cloud Codespace that can be reached from Codex or Claude on Mac/iPhone, wants local-to-remote Codex handoff like the Guinness Chen X post, wants GitHub repo creation/linking for a local project, or wants startup automation for tailscaled, Claude Code, and Codex app-server in a Codespace.
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
   - `claude --version` on the Codespace
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

For fully automatic Tailscale login on first Codespace boot, set `TAILSCALE_AUTHKEY` in the shell before running the script. The script stores it as a user-level GitHub Codespaces secret selected for the target repo and never writes it to Git:

```bash
export TAILSCALE_AUTHKEY='<tailscale-auth-key>'
```

If `TAILSCALE_AUTHKEY` is absent, the script still installs startup automation, but the first Tailscale login may require a manual `tailscale up --ssh --hostname=<name>` or a later secret.

After the Codespace successfully appears in Tailscale, disable key expiry for that device in the Tailscale admin UI if the user wants the host to survive repeated Codespace stop/start cycles without reauth.

Do not diagnose the secret by running `echo "$TAILSCALE_AUTHKEY"` inside a later `gh codespace ssh` shell. Codespaces secrets are available to lifecycle commands such as `postStartCommand`, but they may not be visible in later interactive shells.

## Claude and Codex Login Boundaries

The script installs Claude Code and Codex in the Codespace, but both may still require user authentication:

```bash
claude
codex login --device-auth
```

If `claude` asks for browser login, or if the remote prints a device URL/code for Codex, present it to the user and wait. After they say done, verify:

```bash
claude --version
codex login status
codex app-server daemon version
```

Do not claim the system is complete until remote Codex login and daemon status are verified.

## Codespace Rebuild Rule

Changes to `.devcontainer/devcontainer.json` or `.devcontainer/codespace-startup.sh` require a Codespace rebuild. A stop/start is enough only after those files are already present in the built container.

After stopping a Codespace, wait 3-4 minutes before starting or rebuilding again. GitHub can leave the Codespace in a transitional state if repeated start/stop/rebuild requests are sent too quickly.

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

## Tailscale Node Name Recovery

If a rebuilt Codespace appears as `<name>-1` in Tailscale, there is usually a stale offline machine still holding `<name>`. Delete the stale offline machine in the Tailscale admin UI, then run this on the Codespace:

```bash
sudo tailscale up --ssh --hostname=<name> --accept-dns=false --operator="$USER"
```

The `--operator` flag matters. Once a node has that non-default setting, later `tailscale up` calls must include it or Tailscale can reject the update.
