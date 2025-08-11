## Postfix Mail Server Setup (Ubuntu 20.04/22.04/24.04)

Automated, single-script setup of a full-featured mail server on Ubuntu using Postfix (SMTP), Dovecot (IMAP/POP3/LMTP), OpenDKIM, OpenDMARC, optional SpamAssassin, Fail2ban, UFW, and TLS via Let's Encrypt or self-signed certificates.

### What this sets up
- **Postfix (SMTP)**: submission (587), SMTPS (465), and SMTP (25)
- **Dovecot (IMAP/POP3)**: IMAPS (993), IMAP (143), POP3S (995), POP3 (110)
- **TLS**: **Let's Encrypt** by default, automatic fallback to **self-signed**
- **OpenDKIM + OpenDMARC**: signing and policy enforcement
- **SpamAssassin (optional)**: spam filtering via spamass-milter
- **Fail2ban (optional)**: basic protection for Postfix and Dovecot
- **UFW (optional)**: firewall rules for email and TLS issuance
- **Virtual mailboxes** under `vmail` user with Maildir per user

---

## Requirements
- Fresh or existing Ubuntu server: 20.04, 22.04, or 24.04
- Root access (`sudo`)
- A domain name (e.g. `example.com`) and the ability to create DNS records
- Public IP with proper routing. For production, configure reverse DNS (PTR) to your mail hostname

---

## Quick start
1) Copy the script to your Ubuntu server and make it executable:
```bash
sudo cp setup-postfix-mailserver.sh /usr/local/sbin/
sudo chmod +x /usr/local/sbin/setup-postfix-mailserver.sh
```

2) Run it as root with your domain and hostname. Example using Let's Encrypt:
```bash
sudo bash /usr/local/sbin/setup-postfix-mailserver.sh \
  --mail-domain example.com \
  --hostname mail.example.com \
  --letsencrypt-email admin@example.com
```

If you prefer self-signed certificates:
```bash
sudo bash /usr/local/sbin/setup-postfix-mailserver.sh \
  --mail-domain example.com \
  --use-self-signed
```

3) At the end, the script prints DNS records to create (A/AAAA, MX, SPF, DKIM, DMARC) and shows the seeded postmaster account.

4) Create additional mail users after DNS is set:
```bash
sudo add-mail-user user@example.com 'StrongPassword!'
```

---

## CLI options
Run `sudo bash setup-postfix-mailserver.sh --help` to view help.

- `--mail-domain DOMAIN` (required): Primary mail domain (e.g., `example.com`)
- `--hostname FQDN`: Mail server hostname. Default: `mail.DOMAIN`
- `--admin-email EMAIL`: Admin email for notifications
- `--letsencrypt-email EMAIL`: Email for Let's Encrypt registration
- `--use-self-signed`: Use self-signed certs instead of Let's Encrypt
- `--no-ufw`: Do not configure UFW firewall
- `--no-spamassassin`: Skip SpamAssassin and spamass-milter
- `--no-fail2ban`: Skip Fail2ban setup
- `--ipv4-only`: Disable IPv6 in Postfix/Dovecot
- `-h, --help`: Show usage help

---

## What the script does
- Updates apt, installs required packages
- Configures hostname and `/etc/hosts`
- Obtains TLS certs via Let's Encrypt standalone or generates self-signed certs at `/etc/ssl/mail/`
- Sets up Dovecot: IMAP/POP3, LMTP, passdb at `/etc/dovecot/users` with `SHA512-CRYPT`
- Configures OpenDKIM/OpenDMARC and generates DKIM keys at `/etc/opendkim/keys/DOMAIN/`
- Optionally enables SpamAssassin via spamass-milter
- Configures Postfix for virtual domains, TLS, SASL (Dovecot), milters
- Optionally configures UFW rules and Fail2ban jails
- Enables and restarts all services
- Installs helper commands: `add-mail-user`, `del-mail-user`, `list-mail-users`
- Seeds `postmaster@DOMAIN` with a random password and prints it
- Prints DNS guidance for SPF, DKIM, DMARC, MX, A/AAAA

Backups of edited config files are created as `*.bak-YYYYMMDD-HHMMSS`.

---

## DNS and networking
Create these at your DNS provider (the script also prints them):
- **A**: `mail.example.com -> your IPv4`
- **AAAA**: `mail.example.com -> your IPv6` (if applicable)
- **MX**: `example.com -> mail.example.com (priority 10)`
- **TXT (SPF)** for `example.com`: `"v=spf1 mx a -all"`
- **TXT (DKIM)** for `mail._domainkey.example.com`: value printed from `/etc/opendkim/keys/example.com/mail.txt`
- **TXT (DMARC)** for `_dmarc.example.com`: `"v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; fo=1"`

Additionally for production deliverability:
- Configure reverse DNS (PTR) of your public IP to `mail.example.com`
- Ensure port 25 is reachable from the Internet (some VPS providers block it by default)

---

## Firewall ports
If UFW is enabled by the script, the following are allowed:
- 22/tcp (SSH)
- 25/tcp (SMTP), 465/tcp (SMTPS), 587/tcp (Submission)
- 110/tcp (POP3), 995/tcp (POP3S)
- 143/tcp (IMAP), 993/tcp (IMAPS)
- 80/tcp, 443/tcp (for Let's Encrypt HTTP-01)

---

## Manage mail users
- **Add**: `sudo add-mail-user user@example.com 'Password'`
- **Delete**: `sudo del-mail-user user@example.com [--keep-mail]`
- **List**: `sudo list-mail-users`

User credentials are stored in `/etc/dovecot/users` (format: `user@domain:HASH:...`). Mail is stored in `/var/mail/vhosts/DOMAIN/USER/Maildir`.

---

## Mail client settings (examples)
- Incoming IMAP: host=`mail.example.com`, port=993, SSL/TLS, auth=normal password
- Outgoing SMTP (Submission): host=`mail.example.com`, port=587, STARTTLS, auth=normal password

POP3 alternatives:
- POP3S: port=995, SSL/TLS
- POP3: port=110

---

## Logs and monitoring
- Postfix: `journalctl -u postfix -f`
- Dovecot: `journalctl -u dovecot -f`
- DKIM/DMARC: `journalctl -u opendkim -u opendmarc -f`
- SpamAssassin: `journalctl -u spamassassin -u spamass-milter -f`

---

## Troubleshooting
- **Let's Encrypt failed; using self-signed**: The script auto-falls back. Ensure ports 80/443 are free, DNS `mail.example.com` resolves to this server, and rerun to get LE certs.
- **Ports in use**: Stop conflicting services (e.g., `nginx`, `apache`) during certificate issuance.
- **Cannot send mail externally**: Check provider blocks on port 25, SPF/DKIM/DMARC records, and PTR.
- **Auth failures**: Verify user exists in `/etc/dovecot/users` and restart `dovecot`.
- **Milter socket errors**: Ensure directories exist under `/var/spool/postfix/` for `opendkim` and `spamass`, then restart Postfix and milters.
- **IPv6 issues**: Use `--ipv4-only` if your network lacks IPv6 reachability.
- **Check configs**: `postfix check` and `doveconf -n` can reveal syntax issues.
- **Test TLS/SMTP**:
```bash
openssl s_client -starttls smtp -crlf -connect mail.example.com:587
```

---

## Data locations
- Certificates: `/etc/ssl/mail/` (symlinks to LE if used)
- Dovecot users: `/etc/dovecot/users`
- DKIM keys: `/etc/opendkim/keys/DOMAIN/`
- Mailboxes: `/var/mail/vhosts/DOMAIN/USER/Maildir`
- Backups: `*.bak-YYYYMMDD-HHMMSS` alongside original config files

---

## Uninstall (manual)
This removes packages and most configuration. Mail data under `/var/mail/vhosts/` is preserved unless you delete it.
```bash
sudo systemctl stop postfix dovecot opendkim opendmarc spamassassin spamass-milter 2>/dev/null || true
sudo apt-get remove -y postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-sieve dovecot-managesieved opendkim opendkim-tools opendmarc spamassassin spamc spamass-milter fail2ban ufw
sudo apt-get autoremove -y
# Optional (remove configs; make backups first!)
# sudo rm -rf /etc/postfix /etc/dovecot /etc/opendkim /etc/opendmarc /etc/spamassassin /var/mail/vhosts
```

---

## Notes and best practices
- Prefer a clean VM or container with a static IP.
- Keep the server hostname stable; changing it later requires updating TLS and DNS.
- Regularly back up `/etc/postfix`, `/etc/dovecot`, `/etc/opendkim`, `/etc/opendmarc`, and `/var/mail/vhosts`.
- Monitor bounces and DMARC reports to tune deliverability.

---

## License
This project is provided as-is. Review and adapt to your security and compliance requirements before production use.