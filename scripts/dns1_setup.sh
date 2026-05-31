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

Variables surchargeables :
  BASE_DIR, TF_DIR, ANSIBLE_DIR, INVENTORY, PLAYBOOK, ANSIBLE_GROUP
  VMID, DNS_IP, DNS_HOSTNAME, SSH_KEY, TF_RESOURCE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argument inconnu: $1" >&2; usage; exit 2 ;;
  esac
done

exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
ok()   { printf '  [OK]   %s\n' "$*"; OK_ITEMS+=("$*"); }
warn() { printf '  [WARN] %s\n' "$*"; WARN_ITEMS+=("$*"); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL_ITEMS+=("$*"); }
die()  { printf '\n[ERREUR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Commande manquante: $1"
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
  echo "--- commande ---"
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
  echo "--- commande ---"
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
  log "Attente SSH sur $DNS_IP"
  for _ in $(seq 1 60); do
    if remote true >/dev/null 2>&1; then
      ok "SSH disponible sur $DNS_IP"
      return 0
    fi
    sleep 2
  done
  die "SSH indisponible sur $DNS_IP"
}

print_summary() {
  echo
  echo "============================================================"
  echo "Résumé dns1_setup.sh"
  echo "============================================================"
  echo "Log complet : $LOG_FILE"
  echo
  echo "Points OK :"
  [[ ${#OK_ITEMS[@]} -eq 0 ]] && echo "  Aucun" || printf '  - %s\n' "${OK_ITEMS[@]}"
  echo
  echo "Points en avertissement :"
  [[ ${#WARN_ITEMS[@]} -eq 0 ]] && echo "  Aucun" || printf '  - %s\n' "${WARN_ITEMS[@]}"
  echo
  echo "Points en échec :"
  [[ ${#FAIL_ITEMS[@]} -eq 0 ]] && echo "  Aucun" || printf '  - %s\n' "${FAIL_ITEMS[@]}"
  echo "============================================================"
}

trap 'echo; echo "Erreur ligne $LINENO"; print_summary' ERR
trap 'echo; echo "Interruption utilisateur"; print_summary; exit 130' INT

log "Pré-vérifications"
for cmd in terraform ansible-playbook ansible ssh ssh-keygen dig openssl kdig; do
  require_cmd "$cmd"
done

[[ -d "$TF_DIR" ]] || die "Dossier Terraform introuvable: $TF_DIR"
[[ -d "$ANSIBLE_DIR" ]] || die "Dossier Ansible introuvable: $ANSIBLE_DIR"
[[ -f "$ANSIBLE_DIR/$INVENTORY" ]] || die "Inventaire introuvable: $ANSIBLE_DIR/$INVENTORY"
[[ -f "$ANSIBLE_DIR/$PLAYBOOK" ]] || die "Playbook introuvable: $ANSIBLE_DIR/$PLAYBOOK"
[[ -f "$SSH_KEY" ]] || die "Clé SSH introuvable: $SSH_KEY"
ok "Pré-vérifications locales"

cat <<EOF

ATTENTION : opération destructive.
Ce script va détruire puis recréer le LXC DNS.

  VMID Terraform attendu : $VMID
  Ressource Terraform    : $TF_RESOURCE
  IP DNS                 : $DNS_IP
  Hostname DNS           : $DNS_HOSTNAME
  Terraform dir          : $TF_DIR
  Ansible dir            : $ANSIBLE_DIR

EOF

if [[ "$AUTO_YES" != "true" ]]; then
  read -r -p "Confirmer la destruction/recréation du LXC $VMID ? Tape 'yes' : " confirm
  [[ "$confirm" == "yes" ]] || die "Confirmation refusée"
fi

log "Nettoyage known_hosts pour $DNS_IP"
ssh-keygen -f "$KNOWN_HOSTS" -R "$DNS_IP" >/dev/null 2>&1 || true
ok "Ancienne empreinte SSH supprimée si présente"

log "Initialisation Terraform"
cd "$TF_DIR"
terraform init -input=false
terraform validate
ok "Terraform init/validate OK"

log "Destruction Terraform ciblée du LXC $VMID"
if terraform state list | grep -qx "$TF_RESOURCE"; then
  terraform destroy -target="$TF_RESOURCE" -auto-approve
  # L’usage de -target est volontaire ici dans le cadre du scénario de rebuild contrôlé d’une ressource unique (environnement pour exemple).
  ok "LXC détruit via Terraform"
else
  ok "Aucune ressource Terraform existante à détruire"
fi

ssh-keygen -f "$KNOWN_HOSTS" -R "$DNS_IP" >/dev/null 2>&1 || true
ok "known_hosts nettoyé avant recréation"

log "Création du LXC DNS via Terraform"
terraform apply -auto-approve
ok "LXC créé via Terraform"

wait_for_ssh

log "Validation Ansible ping/pong"
cd "$ANSIBLE_DIR"
ansible -i "$INVENTORY" "$ANSIBLE_GROUP" -m ping
ok "Ansible ping OK"

log "Installation et configuration Unbound via Ansible"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK"
ok "Playbook Ansible terminé sans erreur"

log "Vérifications système Unbound"
check_cmd "unbound-checkconf OK" remote unbound-checkconf || true
check_cmd "service Unbound actif" remote systemctl is-active --quiet unbound || true
check_cmd "écoute UDP/53" remote bash -lc "ss -H -lun 'sport = :53' | grep -q ." || true
check_cmd "écoute TCP/53" remote bash -lc "ss -H -ltn 'sport = :53' | grep -q ." || true
check_cmd "écoute TCP/853" remote bash -lc "ss -H -ltn 'sport = :853' | grep -q ." || true

log "Tests DNS"
check_shell "résolution locale DNS" "dig @$DNS_IP $DNS_HOSTNAME +short | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'" || true
check_shell "résolution externe UDP/53" "dig @$DNS_IP cloudflare.com A +short | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'" || true
check_shell "résolution externe TCP/53" "dig +tcp @$DNS_IP cloudflare.com A +short | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$'" || true
check_shell "DNSSEC valide avec flag AD" "dig @$DNS_IP sigok.verteiltesysteme.net +dnssec | grep -Eq 'flags:.* ad'" || true
check_shell "DNSSEC invalide -> SERVFAIL" "dig @$DNS_IP dnssec-failed.org +time=5 +tries=1 | grep -q 'status: SERVFAIL'" || true
warn_shell "DNSSEC sigfail -> SERVFAIL (test complémentaire)" "for i in 1 2 3; do out=\$(dig @$DNS_IP sigfail.verteiltesysteme.net +time=10 +tries=3); echo \"\$out\"; echo \"\$out\" | grep -q 'status: SERVFAIL' && exit 0; sleep 2; done; exit 1" || true

log "Tests DNS-over-TLS"
check_shell "TLS handshake 853 valide" "echo | openssl s_client -connect $DNS_IP:853 -servername $DNS_HOSTNAME 2>/dev/null | grep -q 'Verify return code: 0 (ok)'" || true
check_shell "requête DoT via kdig" "kdig @$DNS_IP +tls cloudflare.com | grep -q 'status: NOERROR'" || true

print_summary

if [[ ${#FAIL_ITEMS[@]} -gt 0 ]]; then
  echo
  echo "Résultat final : ÉCHEC partiel, voir les points ci-dessus."
  exit 1
fi

echo
echo "Résultat final : OK - DNS est recréé, configuré et fonctionnel sur 53/853."
exit 0
