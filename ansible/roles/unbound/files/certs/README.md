# Note

## Certificats

Avant d’activer DoT, il faut déposer les certificats :
```text
ansible/roles/unbound/files/certs/fullchain.pem
ansible/roles/unbound/files/certs/privkey.pem
```
---

## Setting

Dans le cas ou il n'y a pas de DoT :
unbound_tls_enabled: false

---
