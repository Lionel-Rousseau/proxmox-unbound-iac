#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TF_DIR="${TF_DIR:-$BASE_DIR/terraform/proxmox}"
ANSIBLE_DIR="${ANSIBLE_DIR:-$BASE_DIR/ansible}"
INVENTORY="${INVENTORY:-inventory/prod.yml}"
PLAYBOOK="${PLAYBOOK:-site.yml}"
ANSIBLE_GROUP="${ANSIBLE_GROUP:-dns}"

VMID="${VMID:-150}"
DNS_IP="${DNS_IP:-10.10.10.53}"
DNS_HOSTNAME="${DNS_HOSTNAME:-dns1.lab.example}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
KNOWN_HOSTS="${KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
TF_RESOURCE="${TF_RESOURCE:-proxmox_virtual_environment_container.unbound_01}"

AUTO_YES="false"
LOG_FILE="${LOG_FILE:-/tmp/dns1_setup_$(date +%Y%m%d_%H%M%S).log}"

OK_ITEMS=()
WARN_ITEMS=()
FAIL_ITEMS=()

usage() {
  cat <<EOF
Usage: $0 [--yes]

Overridable variables:
  BASE_DIR, TF_DIR, ANSIBLE_DIR, INVENTORY, PLAYBOOK, ANSIBLE_GROUP
  VMID, DNS_IP, DNS_HOSTNAME, SSH_KEY, KNOWN_HOSTS, TF_RESOURCE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
ok()   { printf '  [OK]   %s\n' "$*"; OK_ITEMS+=("$*"); }
warn() { printf '  [WARN] %s\n' "$*"; WARN_ITEMS+=("$*"); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL_ITEMS+=("$*"); }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

check_cmd() {
  local label="$1"; shift
  if "$@" >/tmp/dns1_check.out 2>/tmp/dns1_check.err; then
    ok "$label"
    return 0
  fi
  fail "$label"
  cat /tmp/dns1_check.out || true
  cat /tmp/dns1_check.err || true
  return 1
}

check_shell() {
  local label="$1"
  local cmd="$2"
  if env -u BASH_ENV bash --noprofile --norc -c "$cmd" >/tmp/dns1_check.out 2>/tmp/dns1_check.err; then
    ok "$label"
    return 0
  fi
  fail "$label"
  echo "--- command ---"
  echo "$cmd"
  echo "--- stdout ---"
  cat /tmp/dns1_check.out || true
  echo "--- stderr ---"
  cat /tmp/dns1_check.err || true
  return 1
}

warn_shell() {
  local label="$1"
  local cmd="$2"
  if env -u BASH_ENV bash --noprofile --norc -c "$cmd" >/tmp/dns1_check.out 2>/tmp/dns1_check.err; then
    ok "$label"
    return 0
  fi
  warn "$label"
  echo "--- command ---"
  echo "$cmd"
  echo "--- stdout ---"
  cat /tmp/dns1_check.out || true
  echo "--- stderr ---"
  cat /tmp/dns1_check.err || true
  return 0
}

remote() {
  ssh \
    -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    root@"$DNS_IP" \
    "$@"
}

wait_for_ssh() {
  log "Waiting for SSH on $DNS_IP"
  for _ in $(seq 1 60); do
    if remote true >/dev/null 2>&1; then
      ok "SSH available on $DNS_IP"
      return 0
    fi
    sleep 2
  done
  die "SSH unavailable on $DNS_IP"
}

print_summary() {
  echo
  echo "============================================================"
  echo "dns1_setup.sh summary"
  echo "============================================================"
  echo "Full log: $LOG_FILE"
  echo
  echo "OK items:"
  [[ ${#OK_ITEMS[@]} -eq 0 ]] && echo "  None" || printf '  - %s\n' "${OK_ITEMS[@]}"
  echo
  echo "Warning items:"
  [[ ${#WARN_ITEMS[@]} -eq 0 ]] && echo "  None" || printf '  - %s\n' "${WARN_ITEMS[@]}"
  echo
  echo "Failure items:"
  [[ ${#FAIL_ITEMS[@]} -eq 0 ]] && echo "  None" || printf '  - %s\n' "${FAIL_ITEMS[@]}"
  echo "============================================================"
}

trap 'echo; echo "Error on line $LINENO"; print_summary' ERR
trap 'echo; echo "User interruption"; print_summary; exit 130' INT

log "Pre-checks"
for cmd in terraform ansible-playbook ansible ssh ssh-keygen dig openssl kdig; do
  require_cmd "$cmd"
done

[[ -d "$TF_DIR" ]] || die "Terraform directory not found: $TF_DIR"
[[ -d "$ANSIBLE_DIR" ]] || die "Ansible directory not found: $ANSIBLE_DIR"
[[ -f "$ANSIBLE_DIR/$INVENTORY" ]] || die "Inventory not found: $ANSIBLE_DIR/$INVENTORY"
[[ -f "$ANSIBLE_DIR/$PLAYBOOK" ]] || die "Playbook not found: $ANSIBLE_DIR/$PLAYBOOK"
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"
ok "Local pre-checks"

cat <<EOF

WARNING: destructive operation.
This script will destroy then recreate the DNS LXC.

  Expected Terraform VMID : $VMID
  Terraform resource      : $TF_RESOURCE
  DNS IP                  : $DNS_IP
  DNS hostname            : $DNS_HOSTNAME
  Terraform dir           : $TF_DIR
  Ansible dir             : $ANSIBLE_DIR

EOF

if [[ "$AUTO_YES" != "true" ]]; then
  read -r -p "Confirm destruction/recreation of LXC $VMID ? Type 'yes': " confirm
  [[ "$confirm" == "yes" ]] || die "Confirmation declined"
fi

log "Cleaning known_hosts for $DNS_IP"
ssh-keygen -f "$KNOWN_HOSTS" -R "$DNS_IP" >/dev/null 2>&1 || true
ok "Old SSH fingerprint removed if present"

log "Terraform initialization"
cd "$TF_DIR"
terraform init -input=false
terraform validate
ok "Terraform init/validate OK"

log "Targeted Terraform destruction of LXC $VMID"
if terraform state list | grep -qx "$TF_RESOURCE"; then
  terraform destroy -target="$TF_RESOURCE" -auto-approve
  # The use of -target is intentional here, as part of a controlled rebuild scenario for a single resource (example environment).
  ok "LXC destroyed via Terraform"
else
  ok "No existing Terraform resource to destroy"
fi

ssh-keygen -f "$KNOWN_HOSTS" -R "$DNS_IP" >/dev/null 2>&1 || true
ok "known_hosts cleaned before recreation"

log "Creating the DNS LXC via Terraform"
terraform apply -auto-approve
ok "LXC created via Terraform"

wait_for_ssh

log "Ansible ping/pong validation"
cd "$ANSIBLE_DIR"
ansible -i "$INVENTORY" "$ANSIBLE_GROUP" -m ping
ok "Ansible ping OK"

log "Installing and configuring Unbound via Ansible"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK"
ok "Ansible playbook completed without error"

log "Unbound system checks"
check_cmd "unbound-checkconf OK" remote unbound-checkconf || true
check_cmd "Unbound service active" remote systemctl is-active --quiet unbound || true
check_cmd "UDP/53 listener" remote bash -lc "ss -H -lun 'sport = :53' | grep -q ." || true
check_cmd "TCP/53 listener" remote bash -lc "ss -H -ltn 'sport = :53' | grep -q ." || true
check_cmd "TCP/853 listener" remote bash -lc "ss -H -ltn 'sport = :853' | grep -q ." || true

log "DNS tests"
check_shell "local DNS resolution" "dig @$DNS_IP $DNS_HOSTNAME +short | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'" || true
check_shell "external resolution UDP/53" "dig @$DNS_IP cloudflare.com A +short | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'" || true
check_shell "external resolution TCP/53" "dig +tcp @$DNS_IP cloudflare.com A +short | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'" || true
check_shell "DNSSEC valid with AD flag" "dig @$DNS_IP sigok.verteiltesysteme.net +dnssec | grep -Eq 'flags:.* ad'" || true
check_shell "DNSSEC invalid -> SERVFAIL" "dig @$DNS_IP dnssec-failed.org +time=5 +tries=1 | grep -q 'status: SERVFAIL'" || true
warn_shell "DNSSEC sigfail -> SERVFAIL (additional test)" "for i in 1 2 3; do out=\$(dig @$DNS_IP sigfail.verteiltesysteme.net +time=10 +tries=3); echo \"\$out\"; echo \"\$out\" | grep -q 'status: SERVFAIL' && exit 0; sleep 2; done; exit 1" || true

log "DNS-over-TLS tests"
check_shell "TLS handshake 853 valid" "echo | openssl s_client -connect $DNS_IP:853 -servername $DNS_HOSTNAME 2>/dev/null | grep -q 'Verify return code: 0 (ok)'" || true
check_shell "DoT query via kdig" "kdig @$DNS_IP +tls cloudflare.com | grep -q 'status: NOERROR'" || true

print_summary

if [[ ${#FAIL_ITEMS[@]} -gt 0 ]]; then
  echo
  echo "Final result: partial FAILURE, see the items above."
  exit 1
fi

echo
echo "Final result: OK - DNS recreated, configured and operational on 53/853."
exit 0
