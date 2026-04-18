#!/bin/bash
set -e

# Ensure required subdirectories exist.
# Named volumes inherit these from the image layer on first run; bind mounts do not,
# which causes the Claude subprocess to fail silently when spawned with a missing cwd.
mkdir -p /.archon/workspaces /.archon/worktrees

# Determine if we need to use gosu for privilege dropping
if [ "$(id -u)" = "0" ]; then
  # Running as root: fix volume permissions, then drop to appuser.
  # chown may fail on macOS bind mounts (VirtioFS does not allow ownership changes
  # from within the container). This is non-fatal: VirtioFS permits writes regardless
  # of the ownership shown by ls, so appuser can operate normally.
  # Note: we must still drop to appuser — Claude Code refuses --dangerously-skip-permissions as root.
  if ! chown -Rh appuser:appuser /.archon 2>/dev/null; then
    echo "WARNING: Could not fix ownership of /.archon (macOS bind mount via VirtioFS?)." >&2
    echo "         Continuing as appuser — VirtioFS allows writes regardless of shown ownership." >&2
  fi
  RUNNER="gosu appuser"
else
  # Already running as non-root (e.g., --user flag or Kubernetes)
  RUNNER=""
fi

# Register all git repositories under /.archon as safe directories for appuser.
# Git 2.35.2+ (CVE-2022-24765) rejects repos where the directory owner differs
# from the running user. On macOS bind mounts (VirtioFS), host-side UIDs (e.g. 501)
# don't map to the container's appuser (1001), so git prints "dubious ownership"
# and refuses all operations. The Dockerfile RUN-layer only registers fixed paths;
# worktrees are nested arbitrarily deep and must be discovered at runtime.
# We run this after chown so the paths are already appuser-owned, which is the
# common case — but we also cover the non-root path (--user flag, Kubernetes).
find /.archon -name ".git" 2>/dev/null | while read -r git_dir; do
  $RUNNER git config --global --add safe.directory "$(dirname "$git_dir")"
done

# Configure git to use GH_TOKEN for HTTPS clones via credential helper
# Uses a helper function so the token stays in the environment, not in ~/.gitconfig
if [ -n "$GH_TOKEN" ]; then
  $RUNNER git config --global credential."https://github.com".helper \
    '!f() { echo "username=x-access-token"; echo "password=${GH_TOKEN}"; }; f'
fi

# Run setup-auth (exits after configuring Codex credentials), then exec the server
# exec ensures bun is PID 1 and receives SIGTERM for graceful shutdown
$RUNNER bun run setup-auth
exec $RUNNER bun run start
