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

ensure_vm_running() {
  status="$($LIMACTL list 2>/dev/null | awk -v name="$VM_NAME" '$1 == name { print $2 }')"

  case "$status" in
    Running)
      ;;
    Stopped)
      "$LIMACTL" start "$VM_NAME" >/dev/null
      ;;
    "")
      echo "Lima VM '$VM_NAME' not found. Create it first or set HOSTKIT_LIMA_VM." >&2
      exit 1
      ;;
    *)
      echo "Lima VM '$VM_NAME' is $status, expected Running." >&2
      exit 1
      ;;
  esac
}

ensure_mix() {
  if ! "$LIMACTL" shell "$VM_NAME" -- sh -lc "command -v mix >/dev/null 2>&1"; then
    echo "mix not found in Lima VM '$VM_NAME'. Install Elixir 1.20+ in the VM and rerun." >&2
    exit 127
  fi
}

copy_repo() {
  repo="$1"
  "$LIMACTL" shell "$VM_NAME" -- sh -lc "rm -rf $REMOTE_BASE/$repo && mkdir -p $REMOTE_BASE/$repo"
  COPYFILE_DISABLE=1 tar -C "$WORKSPACE_DIR/$repo" --exclude=_build --exclude=deps --exclude=doc -cf - . |
    "$LIMACTL" shell "$VM_NAME" -- sh -lc "tar -C $REMOTE_BASE/$repo -xf -"
}

ensure_vm_running
ensure_mix
copy_repo systemdkit
copy_repo unitctl
copy_repo host_kit

"$LIMACTL" shell "$VM_NAME" -- sh -lc "
  cd $REMOTE_DIR &&
  mix deps.get >/dev/null &&
  HOSTKIT_INTEGRATION=1 mix test
"
