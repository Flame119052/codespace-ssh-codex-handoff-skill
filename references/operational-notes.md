# Operational Notes

## Auth Boundaries

- Tailscale can be automated with a reusable auth key stored as the GitHub Codespaces secret `TAILSCALE_AUTHKEY`.
- Do not commit Tailscale keys, OpenAI/Codex auth, SSH private keys, or GitHub tokens.
- Codex ChatGPT login is usually device-code based. Stop and present the device URL/code when required.
- Verify remote login with `codex login status`; "daemon running" is not enough.

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
