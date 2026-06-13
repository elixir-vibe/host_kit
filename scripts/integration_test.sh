#!/usr/bin/env sh
set -eu

VM_NAME="${HOSTKIT_LIMA_VM:-hostkit-test}"
PROJECT_DIR="${HOSTKIT_PROJECT_DIR:-$(pwd)}"
REMOTE_DIR="${HOSTKIT_REMOTE_DIR:-~/hostkit-test-src}"

~/.local/bin/limactl shell "$VM_NAME" -- sh -lc "
  rm -rf $REMOTE_DIR &&
  mkdir -p $REMOTE_DIR &&
  tar -C '$PROJECT_DIR' --exclude=_build --exclude=deps --exclude=doc -cf - . | tar -C $REMOTE_DIR -xf - &&
  cd $REMOTE_DIR &&
  mix deps.get >/dev/null &&
  HOSTKIT_INTEGRATION=1 mix test
"
