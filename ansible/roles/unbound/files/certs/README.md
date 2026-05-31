# Note

## Certificats

Avant d’activer DoT, il faut déposer les certificats :
```text
ansible/roles/unbound/files/certs/fullchain.pem
ansible/roles/unbound/files/certs/privkey.pem
```
---

## Désactivation de DoT

Si DNS-over-TLS n'est pas utilisé, désactiver l'option suivante :
```text
unbound_tls_enabled: false
```
---
