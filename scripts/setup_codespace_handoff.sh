#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  setup_codespace_handoff.sh --repo-dir DIR --github-repo OWNER/REPO [options]

Options:
  --repo-dir DIR             Local project directory.
  --github-repo OWNER/REPO   GitHub repository to create/use.
  --visibility public|private
                             Visibility for repo creation. Default: private.
  --codespace-name NAME      Codespace display name. Default: <repo>-codex-tailscale.
  --ssh-alias ALIAS          Local SSH alias to print/configure. Default: <repo>-codespace-tailscale.
  --machine NAME             Codespace machine. Default: basicLinux32gb.
  --location NAME            Optional Codespaces location, e.g. EastUs, WestEurope.
  --idle-timeout DURATION    Default: 30m.
  --retention-period DURATION
                             Default: 30d.
  --commit-all               Commit all current changes if there are no staged changes.
  --no-create-codespace      Only prepare GitHub repo/devcontainer.
  -h, --help                 Show help.

Environment:
  TAILSCALE_AUTHKEY          Optional. Stored as repo Codespaces secret TAILSCALE_AUTHKEY.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '[handoff-setup] %s\n' "$*"; }

repo_dir=""
github_repo=""
visibility="private"
codespace_name=""
ssh_alias=""
machine="basicLinux32gb"
location=""
idle_timeout="30m"
retention_period="30d"
commit_all="false"
create_codespace="true"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir) repo_dir="${2:-}"; shift 2 ;;
    --github-repo) github_repo="${2:-}"; shift 2 ;;
    --visibility) visibility="${2:-}"; shift 2 ;;
    --codespace-name) codespace_name="${2:-}"; shift 2 ;;
    --ssh-alias) ssh_alias="${2:-}"; shift 2 ;;
    --machine) machine="${2:-}"; shift 2 ;;
    --location) location="${2:-}"; shift 2 ;;
    --idle-timeout) idle_timeout="${2:-}"; shift 2 ;;
    --retention-period) retention_period="${2:-}"; shift 2 ;;
    --commit-all) commit_all="true"; shift ;;
    --no-create-codespace) create_codespace="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$repo_dir" ] || die "--repo-dir is required"
[ -n "$github_repo" ] || die "--github-repo is required"
case "$visibility" in public|private) ;; *) die "--visibility must be public or private" ;; esac

command -v git >/dev/null 2>&1 || die "git is required"
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required"

repo_dir="$(cd "$repo_dir" && pwd)"
repo_name="${github_repo#*/}"
codespace_name="${codespace_name:-${repo_name,,}-codex-tailscale}"
ssh_alias="${ssh_alias:-${repo_name,,}-codespace-tailscale}"

cd "$repo_dir"

if [ ! -d .git ]; then
  log "initializing git repository"
  git init
fi

mkdir -p .devcontainer
cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "$repo_name",
  "postStartCommand": "bash .devcontainer/codespace-startup.sh"
}
EOF

cat > .devcontainer/codespace-startup.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

log() { printf '[codespace-startup] %s\n' "$*"; }

start_tailscale() {
  if ! command -v tailscaled >/dev/null 2>&1 || ! command -v tailscale >/dev/null 2>&1; then
    log "tailscale is not installed; skipping"
    return 0
  fi

  sudo mkdir -p /var/lib/tailscale /var/run/tailscale

  if ! tailscale status --self >/dev/null 2>&1; then
    log "starting tailscaled"
    sudo nohup tailscaled \
      --state=/var/lib/tailscale/tailscaled.state \
      --socket=/var/run/tailscale/tailscaled.sock \
      >/tmp/codespace-tailscaled.log 2>&1 &
    sleep 3
  fi

  sudo tailscale set --operator="$USER" >/dev/null 2>&1 || true

  if tailscale status --self >/dev/null 2>&1; then
    log "tailscale is running"
    return 0
  fi

  if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    host="${CODESPACE_NAME:-codespace}"
    host="${host%%.*}"
    log "authenticating tailscale as ${host}"
    sudo tailscale up \
      --authkey="$TAILSCALE_AUTHKEY" \
      --ssh \
      --hostname="$host" \
      --accept-dns=false
  else
    log "tailscale is not authenticated; set repo Codespaces secret TAILSCALE_AUTHKEY or run tailscale up manually"
  fi
}

ensure_codex() {
  if [ ! -x "$HOME/.codex/packages/standalone/current/codex" ]; then
    log "installing Codex standalone CLI"
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
  fi

  "$HOME/.codex/packages/standalone/current/codex" app-server daemon bootstrap >/dev/null 2>&1 || true
  "$HOME/.codex/packages/standalone/current/codex" app-server daemon enable-remote-control >/dev/null 2>&1 || true
  "$HOME/.codex/packages/standalone/current/codex" app-server daemon start >/dev/null 2>&1 || true
  log "codex app-server daemon requested"
}

start_tailscale
ensure_codex
EOF
chmod +x .devcontainer/codespace-startup.sh

log "wrote .devcontainer startup files"

if ! gh auth status >/dev/null 2>&1; then
  die "gh is not authenticated; run gh auth login first"
fi

if ! gh repo view "$github_repo" >/dev/null 2>&1; then
  log "creating GitHub repo $github_repo ($visibility)"
  gh repo create "$github_repo" "--$visibility" --source "$repo_dir" --remote origin --push
else
  log "GitHub repo exists: $github_repo"
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/${github_repo}.git"
  fi
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ "$origin_url" != "https://github.com/${github_repo}.git" ] && [ "$origin_url" != "git@github.com:${github_repo}.git" ]; then
  log "setting origin to https://github.com/${github_repo}.git"
  git remote set-url origin "https://github.com/${github_repo}.git"
fi

git add .devcontainer/devcontainer.json .devcontainer/codespace-startup.sh

if git diff --cached --quiet; then
  log "no devcontainer changes to commit"
else
  git commit -m "Start Codex remote services in Codespaces"
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  if [ "$commit_all" = "true" ]; then
    git add -A
    git commit -m "Initial project commit"
  else
    die "repository has no commit; rerun with --commit-all after reviewing files"
  fi
fi

branch="$(git branch --show-current)"
[ -n "$branch" ] || branch="master"
git push -u origin "$branch"

if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
  log "storing TAILSCALE_AUTHKEY as GitHub Codespaces secret"
  gh secret set TAILSCALE_AUTHKEY -R "$github_repo" --app codespaces --body "$TAILSCALE_AUTHKEY"
else
  log "TAILSCALE_AUTHKEY not set; first Tailscale auth may require manual login"
fi

if [ "$create_codespace" = "true" ]; then
  args=(codespace create -R "$github_repo" -b "$branch" --display-name "$codespace_name" --machine "$machine" --idle-timeout "$idle_timeout" --retention-period "$retention_period" --default-permissions)
  if [ -n "$location" ]; then
    args+=(--location "$location")
  fi
  log "creating Codespace $codespace_name"
  gh "${args[@]}"
fi

cat <<EOF

Setup requested.

GitHub repo:
  https://github.com/$github_repo

Codespace:
  display name: $codespace_name
  repo path:    /workspaces/$repo_name

Codex Desktop remote project:
  SSH alias:    $ssh_alias
  remote path:  /workspaces/$repo_name

After the Codespace starts, verify with:
  gh codespace ssh -c "$codespace_name" -- 'tailscale ip -4; codex login status; codex app-server daemon version'

If Codex says "Not logged in", run:
  gh codespace ssh -c "$codespace_name" -- 'codex login --device-auth'

If Tailscale prints a new IP, configure local SSH alias "$ssh_alias" to use that IP with:
  User codespace
  Port 22
  HostName <tailscale-ip>

EOF
