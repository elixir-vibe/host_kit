#!/usr/bin/env sh
set -eu

INSTANCE_NAME="${HOSTKIT_INCUS_INSTANCE:-${HOSTKIT_INCUS_VM:-hostkit-test}}"
IMAGE="${HOSTKIT_INCUS_IMAGE:-images:ubuntu/24.04}"
TYPE="${HOSTKIT_INCUS_TYPE:-container}"
INCUS_BIN="${INCUS:-incus}"
INCUS_SUDO="${HOSTKIT_INCUS_SUDO:-false}"
PUBKEY="${HOSTKIT_SSH_PUBLIC_KEY:-$HOME/.ssh/id_rsa.pub}"

usage() {
  cat >&2 <<EOF
Usage: $0 COMMAND

Commands:
  install       Install Incus with apt if missing
  init          Initialize Incus with --minimal if needed
  ensure        Install, initialize, create/start the test instance, and install SSH
  create        Create/start the test instance and install SSH
  ip            Print the instance IP address
  ssh-config    Print an OpenSSH config entry for the instance
  destroy       Delete the test instance
  status        Show instance status

Environment:
  HOSTKIT_INCUS_INSTANCE    instance name (default: hostkit-test)
  HOSTKIT_INCUS_VM          legacy fallback for HOSTKIT_INCUS_INSTANCE
  HOSTKIT_INCUS_IMAGE       image alias (default: images:ubuntu/24.04)
  HOSTKIT_INCUS_TYPE        container or vm (default: container)
  HOSTKIT_INCUS_SUDO        run incus through sudo: true/false (default: false)
  HOSTKIT_SSH_PUBLIC_KEY    public key to authorize for root SSH
  INCUS                     incus executable (default: incus)
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
    echo "incus not found. Run: $0 install" >&2
    exit 127
  fi
}

install_incus() {
  if command -v "$INCUS_BIN" >/dev/null 2>&1; then
    return 0
  fi

  sudo apt-get update
  sudo apt-get install -y incus
}

init_incus() {
  need_incus

  if incus_cmd storage show default >/dev/null 2>&1 && \
    incus_cmd profile show default 2>/dev/null | grep -q "pool: default"; then
    return 0
  fi

  incus_cmd admin init --minimal
}

instance_exists() {
  incus_cmd info "$INSTANCE_NAME" >/dev/null 2>&1
}

create_instance() {
  need_incus

  if [ ! -r "$PUBKEY" ]; then
    echo "public key not readable: $PUBKEY" >&2
    exit 1
  fi

  if ! instance_exists; then
    echo "[hostkit:incus] launch $TYPE $INSTANCE_NAME from $IMAGE" >&2
    case "$TYPE" in
      container)
        incus_cmd launch "$IMAGE" "$INSTANCE_NAME"
        ;;
      vm)
        incus_cmd launch "$IMAGE" "$INSTANCE_NAME" --vm
        ;;
      *)
        echo "unsupported HOSTKIT_INCUS_TYPE=$TYPE, expected container or vm" >&2
        exit 1
        ;;
    esac
  else
    echo "[hostkit:incus] start existing $INSTANCE_NAME" >&2
    incus_cmd start "$INSTANCE_NAME" >/dev/null 2>&1 || true
  fi

  wait_ready
  install_ssh
}

wait_ready() {
  echo "[hostkit:incus] wait for instance exec readiness" >&2
  i=0
  while [ "$i" -lt 120 ]; do
    if incus_cmd exec "$INSTANCE_NAME" -- true >/dev/null 2>&1; then
      break
    fi
    if [ $((i % 10)) -eq 0 ]; then
      echo "[hostkit:incus] still waiting for $INSTANCE_NAME (${i}s)" >&2
    fi
    i=$((i + 1))
    sleep 1
  done

  if [ "$i" -ge 120 ]; then
    echo "instance $INSTANCE_NAME did not become ready" >&2
    exit 1
  fi

  echo "[hostkit:incus] wait for cloud-init (if present)" >&2
  incus_cmd exec "$INSTANCE_NAME" -- cloud-init status --wait >/dev/null 2>&1 || true
  echo "[hostkit:incus] instance ready" >&2
}

install_ssh() {
  echo "[hostkit:incus] apt-get update" >&2
  incus_cmd exec "$INSTANCE_NAME" -- env DEBIAN_FRONTEND=noninteractive apt-get update
  echo "[hostkit:incus] apt-get install openssh-server sudo ca-certificates curl git" >&2
  incus_cmd exec "$INSTANCE_NAME" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sudo ca-certificates curl git
  incus_cmd exec "$INSTANCE_NAME" -- mkdir -p /root/.ssh
  incus_cmd exec "$INSTANCE_NAME" -- chmod 700 /root/.ssh
  incus_cmd file push "$PUBKEY" "$INSTANCE_NAME/root/.ssh/authorized_keys" --uid 0 --gid 0 --mode 0600

  if incus_cmd exec "$INSTANCE_NAME" -- systemctl is-active --quiet ssh >/dev/null 2>&1; then
    echo "[hostkit:incus] ssh already active" >&2
    return 0
  fi

  echo "[hostkit:incus] start ssh" >&2
  incus_cmd exec "$INSTANCE_NAME" -- sh -c 'timeout 30s service ssh start >/dev/null 2>&1 || timeout 30s systemctl start ssh >/dev/null 2>&1 || true'

  if ! incus_cmd exec "$INSTANCE_NAME" -- systemctl is-active --quiet ssh >/dev/null 2>&1; then
    echo "ssh did not become active" >&2
    exit 1
  fi
}

instance_ip() {
  need_incus

  ip=$(incus_cmd list "$INSTANCE_NAME" -c 4 --format csv | tr ' ' '\n' | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }')

  if [ -z "${ip:-}" ]; then
    echo "could not determine IPv4 address for $INSTANCE_NAME" >&2
    exit 1
  fi

  printf '%s\n' "$ip"
}

ssh_config() {
  ip=$(instance_ip)
  cat <<EOF
Host $INSTANCE_NAME
  HostName $ip
  User root
  StrictHostKeyChecking accept-new
EOF
}

destroy_instance() {
  need_incus
  incus_cmd delete "$INSTANCE_NAME" --force
}

status() {
  need_incus
  incus_cmd list "$INSTANCE_NAME"
}

ensure() {
  install_incus
  init_incus
  create_instance
}

case "${1:-}" in
  install) install_incus ;;
  init) init_incus ;;
  ensure) ensure ;;
  create) create_instance ;;
  ip) instance_ip ;;
  ssh-config) ssh_config ;;
  destroy) destroy_instance ;;
  status) status ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
