#!/usr/bin/env sh
set -eu

INSTANCE_NAME="${HOSTKIT_LIVEBOOK_DEMO_VM:-hostkit-livebook-demo}"
IMAGE="${HOSTKIT_LIVEBOOK_DEMO_IMAGE:-images:ubuntu/24.04}"
SSH_PORT="${HOSTKIT_LIVEBOOK_DEMO_SSH_PORT:-2222}"
PASSWORD="${HOSTKIT_LIVEBOOK_DEMO_PASSWORD:-hostkit-demo}"
INCUS_BIN="${INCUS:-incus}"
INCUS_SUDO="${HOSTKIT_INCUS_SUDO:-false}"

usage() {
  cat >&2 <<EOF
Usage: $0 COMMAND

Commands:
  ensure   Create/start a local Incus demo target with SSH password auth
  destroy  Delete the demo target
  status   Show target status

Defaults for Livebook:
  Server:       127.0.0.1
  SSH user:     root
  SSH password: $PASSWORD
  SSH port:     $SSH_PORT

Environment:
  HOSTKIT_LIVEBOOK_DEMO_VM        instance name (default: hostkit-livebook-demo)
  HOSTKIT_LIVEBOOK_DEMO_IMAGE     Incus image (default: images:ubuntu/24.04)
  HOSTKIT_LIVEBOOK_DEMO_SSH_PORT  host SSH port (default: 2222)
  HOSTKIT_LIVEBOOK_DEMO_PASSWORD  root password (default: hostkit-demo)
  HOSTKIT_INCUS_SUDO              run incus through sudo: true/false (default: false)
  INCUS                           incus executable (default: incus)
EOF
}

incus_cmd() {
  if [ "$INCUS_SUDO" = "true" ]; then
    sudo "$INCUS_BIN" "$@"
  else
    "$INCUS_BIN" "$@"
  fi
}

need_incus() {
  if ! command -v "$INCUS_BIN" >/dev/null 2>&1; then
    echo "incus not found" >&2
    exit 127
  fi
}

instance_exists() {
  incus_cmd info "$INSTANCE_NAME" >/dev/null 2>&1
}

wait_ready() {
  echo "[hostkit:livebook-demo] wait for $INSTANCE_NAME" >&2
  i=0
  while [ "$i" -lt 120 ]; do
    if incus_cmd exec "$INSTANCE_NAME" -- true >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done

  echo "instance $INSTANCE_NAME did not become ready" >&2
  exit 1
}

configure_ssh() {
  echo "[hostkit:livebook-demo] install ssh" >&2
  incus_cmd exec "$INSTANCE_NAME" -- env DEBIAN_FRONTEND=noninteractive apt-get update
  incus_cmd exec "$INSTANCE_NAME" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sudo ca-certificates curl git

  echo "[hostkit:livebook-demo] enable root password login" >&2
  incus_cmd exec "$INSTANCE_NAME" -- sh -c "printf 'root:%s\n' '$PASSWORD' | chpasswd"
  incus_cmd exec "$INSTANCE_NAME" -- sh -c 'install -d -m 0755 /etc/ssh/sshd_config.d && cat >/etc/ssh/sshd_config.d/99-hostkit-livebook-demo.conf <<EOF
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
EOF'
  incus_cmd exec "$INSTANCE_NAME" -- sh -c 'systemctl restart ssh 2>/dev/null || service ssh restart'
}

configure_proxy() {
  if incus_cmd config device show "$INSTANCE_NAME" | grep -q '^sshproxy:'; then
    incus_cmd config device remove "$INSTANCE_NAME" sshproxy >/dev/null 2>&1 || true
  fi

  if incus_cmd config device show "$INSTANCE_NAME" | grep -q '^web18080:'; then
    incus_cmd config device remove "$INSTANCE_NAME" web18080 >/dev/null 2>&1 || true
  fi

  echo "[hostkit:livebook-demo] expose ssh on 127.0.0.1:$SSH_PORT" >&2
  incus_cmd config device add "$INSTANCE_NAME" sshproxy proxy \
    "listen=tcp:127.0.0.1:$SSH_PORT" \
    connect=tcp:127.0.0.1:22

  echo "[hostkit:livebook-demo] expose demo site on 127.0.0.1:18080" >&2
  incus_cmd config device add "$INSTANCE_NAME" web18080 proxy \
    listen=tcp:127.0.0.1:18080 \
    connect=tcp:127.0.0.1:18080
}

ensure() {
  need_incus

  if ! instance_exists; then
    echo "[hostkit:livebook-demo] launch $INSTANCE_NAME from $IMAGE" >&2
    incus_cmd launch "$IMAGE" "$INSTANCE_NAME"
  else
    echo "[hostkit:livebook-demo] start existing $INSTANCE_NAME" >&2
    incus_cmd start "$INSTANCE_NAME" >/dev/null 2>&1 || true
  fi

  wait_ready
  configure_ssh
  configure_proxy

  cat <<EOF

Livebook target ready:
  Server:       127.0.0.1
  SSH user:     root
  SSH password: $PASSWORD
  SSH port:     $SSH_PORT
EOF
}

destroy() {
  need_incus
  incus_cmd delete "$INSTANCE_NAME" --force
}

status() {
  need_incus
  incus_cmd list "$INSTANCE_NAME"
}

case "${1:-}" in
  ensure) ensure ;;
  destroy) destroy ;;
  status) status ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
