# Validation

This page lists the checks performed after rebuilding the Unbound LXC.

## Service

```bash
unbound-checkconf
systemctl is-active unbound
ss -lntup | grep -E ':53|:853'
```

Expected result:
- Unbound active ;
- UDP/53 listener ;
- TCP/53 listener ;
- TCP/853 listener.
- 
## Standard DNS

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

Expected result:

- valid domain: response with the `ad` flag ;
- invalid domain: `SERVFAIL`.
- 
## DNS-over-TLS

```bash
openssl s_client -connect 10.10.10.53:853 -servername dns1.lab.example
kdig @10.10.10.53 +tls cloudflare.com
```

Note:
The openssl s_client test requires a certificate signed by a CA trusted
by the host system. For a self-signed or internal-CA certificate,
add -CAfile /path/to/ca.pem.

Expected result:
- valid TLS handshake ;
- DNS response `NOERROR` over TCP/853.
