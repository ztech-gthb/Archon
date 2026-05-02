#!/bin/bash
set -e

# Ensure required subdirectories exist.
# Named volumes inherit these from the image layer on first run; bind mounts do not,
# which causes the Claude subprocess to fail silently when spawned with a missing cwd.
mkdir -p /.archon/workspaces /.archon/worktrees

# Determine if we need to use gosu for privilege dropping
if [ "$(id -u)" = "0" ]; then
  # Running as root: try to fix volume permissions, then drop to appuser.
  # chown may fail on bind mounts (e.g. macOS VirtioFS) where the host controls
  # ownership — treat this as a warning and fall back to running as root so the
  # container still starts rather than crash-looping.
  if chown -Rh appuser:appuser /.archon 2>/dev/null; then
    RUNNER="gosu appuser"
  else
    echo "WARNING: Could not fix ownership of /.archon (bind mount with incompatible options?) — running as root" >&2
    # Running as root inside Docker is still a sandboxed environment.
    # IS_SANDBOX=1 tells ClaudeProvider to skip the UID-0 safety check.
    export IS_SANDBOX=1
    RUNNER=""
  fi
else
  # Already running as non-root (e.g., --user flag or Kubernetes)
  RUNNER=""
fi

# Configure git to use GH_TOKEN for HTTPS clones via credential helper
# Uses a helper function so the token stays in the environment, not in ~/.gitconfig
if [ -n "$GH_TOKEN" ]; then
  $RUNNER git config --global credential."https://github.com".helper \
    '!f() { echo "username=x-access-token"; echo "password=${GH_TOKEN}"; }; f'
fi

# Register all git repositories under /.archon as safe directories for appuser.
# Git 2.35.2+ (CVE-2022-24765) rejects repos where the directory owner differs
# from the running user. On macOS bind mounts (VirtioFS), host-side UIDs (e.g. 501)
# don't map to the container's appuser (1001), so git prints "dubious ownership"
# and refuses all operations. The Dockerfile RUN-layer only registers fixed paths;
# worktrees are nested arbitrarily deep and must be discovered at runtime.
# We run this after chown so the paths are already appuser-owned, which is the
# common case — but we also cover the non-root path (--user flag, Kubernetes).
find /.archon -name ".git" -prune -print 2>/dev/null | while IFS= read -r git_dir; do
  repo_dir="$(dirname "$git_dir")"
  $RUNNER git config --global --add safe.directory "$repo_dir" 2>/dev/null || true
done

# Run setup-auth (exits after configuring Codex credentials), then exec the server
# exec ensures bun is PID 1 and receives SIGTERM for graceful shutdown
$RUNNER bun run setup-auth
exec $RUNNER bun run start
