#!/usr/bin/env sh
set -eu

VM_NAME="${HOSTKIT_LIMA_VM:-hostkit-test}"
ELIXIR_VERSION="${HOSTKIT_ELIXIR_VERSION:-1.20.1}"
ERLANG_VERSION="${HOSTKIT_ERLANG_VERSION:-29.0.2}"
LIMACTL="${LIMACTL:-limactl}"

if ! command -v "$LIMACTL" >/dev/null 2>&1; then
  if [ -x "$HOME/.local/bin/limactl" ]; then
    LIMACTL="$HOME/.local/bin/limactl"
  else
    echo "limactl not found. Install Lima or set LIMACTL=/path/to/limactl." >&2
    exit 127
  fi
fi

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

"$LIMACTL" shell "$VM_NAME" -- sh -lc "
  set -eu

  sudo apt-get update
  sudo apt-get install -y \
    autoconf \
    build-essential \
    ca-certificates \
    curl \
    git \
    libncurses-dev \
    libssl-dev \
    m4 \
    unzip \
    xsltproc

  if ! command -v mise >/dev/null 2>&1; then
    curl https://mise.run | sh
  fi

  export PATH=\"\$HOME/.local/bin:\$PATH\"
  mise use -g erlang@$ERLANG_VERSION elixir@$ELIXIR_VERSION
  mise exec erlang@$ERLANG_VERSION elixir@$ELIXIR_VERSION -- mix local.hex --force
  mise exec erlang@$ERLANG_VERSION elixir@$ELIXIR_VERSION -- mix local.rebar --force

  if ! grep -q 'mise activate sh' \$HOME/.profile 2>/dev/null; then
    printf '\nexport PATH=\"\$HOME/.local/bin:\$PATH\"\neval \"\$(mise activate sh)\"\n' >> \$HOME/.profile
  fi
"
