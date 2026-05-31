Avant d’activer DoT, il faut déposer les certificats :
ansible/roles/unbound/files/certs/fullchain.pem
ansible/roles/unbound/files/certs/privkey.pem

Dans le cas ou il n'y a pas de DoT :
unbound_tls_enabled: false
