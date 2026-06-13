#!/usr/bin/env sh
set -eu

VM_NAME="${HOSTKIT_LIMA_VM:-hostkit-test}"
WORKSPACE_DIR="${HOSTKIT_WORKSPACE_DIR:-$(cd .. && pwd)}"
REMOTE_BASE="${HOSTKIT_REMOTE_BASE:-~/hostkit-integration}"
REMOTE_DIR="$REMOTE_BASE/host_kit"
LIMACTL="${LIMACTL:-limactl}"

if ! command -v "$LIMACTL" >/dev/null 2>&1; then
  if [ -x "$HOME/.local/bin/limactl" ]; then
    LIMACTL="$HOME/.local/bin/limactl"
  else
    echo "limactl not found. Install Lima or set LIMACTL=/path/to/limactl." >&2
    exit 127
  fi
fi

copy_repo() {
  repo="$1"
  "$LIMACTL" shell "$VM_NAME" -- sh -lc "rm -rf $REMOTE_BASE/$repo && mkdir -p $REMOTE_BASE/$repo"
  tar -C "$WORKSPACE_DIR/$repo" --exclude=_build --exclude=deps --exclude=doc -cf - . |
    "$LIMACTL" shell "$VM_NAME" -- tar -C "$REMOTE_BASE/$repo" -xf -
}

copy_repo systemdkit
copy_repo unitctl
copy_repo host_kit

"$LIMACTL" shell "$VM_NAME" -- sh -lc "
  cd $REMOTE_DIR &&
  mix deps.get >/dev/null &&
  HOSTKIT_INTEGRATION=1 mix test
"
