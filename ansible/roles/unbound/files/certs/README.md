# Note

## Certificates

Before enabling DoT, you must place the certificates:

```text
ansible/roles/unbound/files/certs/fullchain.pem
ansible/roles/unbound/files/certs/privkey.pem
```
---

## Disabling DoT

If DNS-over-TLS is not used, disable the following option:

```text
unbound_tls_enabled: false
```
---
