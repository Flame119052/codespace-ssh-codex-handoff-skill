# Operational Notes

## Auth Boundaries

- Tailscale can be automated with a reusable auth key stored as a user-level GitHub Codespaces secret named `TAILSCALE_AUTHKEY`, selected for the target repo.
- Do not commit Tailscale keys, OpenAI/Codex auth, SSH private keys, or GitHub tokens.
- Claude Code installation is automated; first login may still require `claude` interactive auth.
- Codex ChatGPT login is usually device-code based. Stop and present the device URL/code when required.
- Verify remote login with `codex login status`; "daemon running" is not enough.
- After the device appears in Tailscale, disable key expiry for that device if the user wants persistent stop/start behavior.

## Tailscale Startup Caveats

- Devcontainer changes require a Codespace rebuild. A normal stop/start only uses startup files that already exist in the built Codespace.
- Wait 3-4 minutes after stopping a Codespace before starting or rebuilding. GitHub can remain in a transitional state after shutdown.
- `TAILSCALE_AUTHKEY` may be available to `postStartCommand` while not being visible in a later interactive `gh codespace ssh` shell. Do not treat a missing shell env var as proof that startup could not use the secret.
- Use a user-level Codespaces secret selected for the repo:

```bash
printf '%s' "$TAILSCALE_AUTHKEY" | gh secret set TAILSCALE_AUTHKEY --user --app codespaces --repos OWNER/REPO
gh api user/codespaces/secrets/TAILSCALE_AUTHKEY/repositories
```

- If Tailscale creates `<name>-1`, delete the stale offline `<name>` machine in the Tailscale admin UI, then rerun:

```bash
sudo tailscale up --ssh --hostname=<name> --accept-dns=false --operator="$USER"
```

- Include `--operator="$USER"` in repeated `tailscale up` calls. Tailscale can reject updates when a previous non-default operator setting is omitted.

## Phone Password

With Tailscale SSH, the SSH password field in Codex Mobile may be ignored. If the UI requires non-empty text, use a harmless placeholder such as `codespace`; authorization is handled by Tailscale identity, not that password.

## Master Branch vs Worktrees

The main Codespace checkout is usually `/workspaces/<RepoName>` on `master` or the default branch. Codex handoff creates or uses a worktree. Git refuses to check out the same branch in two worktrees:

```text
fatal: '<branch>' is already used by worktree at '/workspaces/<RepoName>'
```

Use worktree-backed Codex threads for handoff. If the user insists on direct `master`, start the thread directly on the remote project instead of handing off a local thread into another worktree.

## Duplicate Remote Projects

Keep one remote project per Codespace:

```text
/workspaces/<RepoName>
```

Remove older aliases like `/Users/<local-user>/Documents/<RepoName>` or stale GitHub-proxy hosts. If the Codex app still shows duplicates after state cleanup, restart/refresh the app because `list_projects` may reflect in-memory cache.

## Verification Checklist

Use real checks:

```bash
gh codespace list
ssh <alias> 'hostname; pwd; tailscale ip -4; codex login status; codex app-server daemon version'
git -C <repo> status --short --branch
```

Then create a remote smoke thread in `/workspaces/<RepoName>` and, if requested, a separate worktree-backed handoff smoke test.
