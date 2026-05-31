# Validation

Cette page liste les contrôles effectués après reconstruction du LXC Unbound.

## Service

```bash
unbound-checkconf
systemctl is-active unbound
ss -lntup | grep -E ':53|:853'
```

Résultat attendu :

- Unbound actif ;
- écoute UDP/53 ;
- écoute TCP/53 ;
- écoute TCP/853.

## DNS classique

```bash
dig @10.10.10.53 dns1.lab.example +short
dig @10.10.10.53 cloudflare.com A +short
dig +tcp @10.10.10.53 cloudflare.com A +short
```

## DNSSEC

```bash
dig @10.10.10.53 sigok.verteiltesysteme.net +dnssec
dig @10.10.10.53 dnssec-failed.org +time=5 +tries=1
```

Résultat attendu :

- domaine valide : réponse avec flag `ad` ;
- domaine invalide : `SERVFAIL`.

## DNS-over-TLS

```bash
openssl s_client -connect 10.10.10.53:853 -servername dns1.lab.example
kdig @10.10.10.53 +tls cloudflare.com
```

Note:
Le test openssl s_client exige un certificat signé par une CA reconnue 
par le système d'exécution. Pour un cert auto-signé ou de CA interne, 
ajouter -CAfile /chemin/vers/ca.pem.

Résultat attendu :

- handshake TLS valide ;
- réponse DNS `NOERROR` sur TCP/853.
