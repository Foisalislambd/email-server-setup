#!/usr/bin/env bash
set -Eeuo pipefail

# setup-postfix-mailserver.sh
# Fully automated setup of a complete Postfix mail server on Ubuntu (20.04/22.04/24.04)
# Components: Postfix (MTA), Dovecot (IMAP/POP3/LMTP), TLS (Let's Encrypt or self-signed),
# OpenDKIM, OpenDMARC, SpamAssassin (via spamass-milter), Fail2ban, UFW
# Virtual mailboxes with vmail user, Dovecot passdb file, LMTP delivery to Maildir.
#
# Usage examples:
#   sudo bash setup-postfix-mailserver.sh --mail-domain example.com --hostname mail.example.com --admin-email admin@example.com
#   sudo bash setup-postfix-mailserver.sh --mail-domain example.com --use-self-signed
#
# After install, add a mailbox:
#   sudo add-mail-user user@example.com 'StrongPassword!'
#   sudo list-mail-users
#
# DNS records to set will be printed at the end (SPF, DKIM, DMARC, MX, A/AAAA).

########################################
# Config & arg parsing
########################################

SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/var/log/${SCRIPT_NAME%.sh}.log"
UBUNTU_SUPPORTED=("20.04" "22.04" "24.04")

MAIL_DOMAIN=""
MAIL_HOSTNAME=""
ADMIN_EMAIL=""
LETSENCRYPT_EMAIL=""
USE_SELFSIGNED=false
ENABLE_UFW=true
ENABLE_SPAMASSASSIN=true
ENABLE_FAIL2BAN=true
ENABLE_IPV6=true

function log_info() { echo -e "[INFO ] $*" | tee -a "$LOG_FILE"; }
function log_warn() { echo -e "[WARN ] $*" | tee -a "$LOG_FILE"; }
function log_error() { echo -e "[ERROR] $*" | tee -a "$LOG_FILE" >&2; }

function usage() {
  cat <<EOF
$SCRIPT_NAME - Automated Postfix mail server setup for Ubuntu

Required:
  --mail-domain DOMAIN         Primary mail domain, e.g. example.com

Optional:
  --hostname FQDN              Hostname, default: mail.
  --admin-email EMAIL          Admin email for notifications
  --letsencrypt-email EMAIL    Email for Let's Encrypt registration
  --use-self-signed            Use self-signed certs instead of Let's Encrypt
  --no-ufw                     Do not configure UFW firewall
  --no-spamassassin            Do not install SpamAssassin/milter
  --no-fail2ban                Do not install Fail2ban
  --ipv4-only                  Disable IPv6 in Postfix/Dovecot
  -h, --help                   Show this help

Examples:
  sudo bash $SCRIPT_NAME --mail-domain example.com --hostname mail.example.com --letsencrypt-email admin@example.com
  sudo bash $SCRIPT_NAME --mail-domain example.com --use-self-signed --no-ufw
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mail-domain)
      MAIL_DOMAIN="$2"; shift 2;;
    --hostname)
      MAIL_HOSTNAME="$2"; shift 2;;
    --admin-email)
      ADMIN_EMAIL="$2"; shift 2;;
    --letsencrypt-email)
      LETSENCRYPT_EMAIL="$2"; shift 2;;
    --use-self-signed)
      USE_SELFSIGNED=true; shift;;
    --no-ufw)
      ENABLE_UFW=false; shift;;
    --no-spamassassin)
      ENABLE_SPAMASSASSIN=false; shift;;
    --no-fail2ban)
      ENABLE_FAIL2BAN=false; shift;;
    --ipv4-only)
      ENABLE_IPV6=false; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      log_error "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root."; exit 1
fi

if [[ -z "$MAIL_DOMAIN" ]]; then
  log_error "--mail-domain is required."; usage; exit 1
fi

if [[ -z "$MAIL_HOSTNAME" ]]; then
  MAIL_HOSTNAME="mail.${MAIL_DOMAIN}"
fi

if ! command -v hostnamectl >/dev/null 2>&1; then
  log_error "hostnamectl not found; this script targets Ubuntu."; exit 1
fi

OS_NAME=$(lsb_release -is 2>/dev/null || echo "Ubuntu")
OS_VER=$(lsb_release -rs 2>/dev/null || echo "")
if [[ "$OS_NAME" != "Ubuntu" ]]; then
  log_error "This script is intended for Ubuntu only. Detected: $OS_NAME $OS_VER"; exit 1
fi

SUPPORTED=false
for v in "${UBUNTU_SUPPORTED[@]}"; do
  if [[ "$OS_VER" == "$v" ]]; then SUPPORTED=true; fi
  # Accept minor variants like 24.04.1
  if [[ "$OS_VER" == $v* ]]; then SUPPORTED=true; fi
done
if [[ "$SUPPORTED" != true ]]; then
  log_warn "Ubuntu $OS_VER not in tested versions (${UBUNTU_SUPPORTED[*]}). Proceeding anyway."
fi

log_info "Logging to $LOG_FILE"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

########################################
# Helpers
########################################

function backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak-${TIMESTAMP}"
    log_info "Backed up $f -> ${f}.bak-${TIMESTAMP}"
  fi
}

function apt_install() {
  local pkgs=("$@")
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}

function ensure_user_group() {
  local user="$1" gid="$2" uid="$3" home="$4"
  if ! getent group "$gid" >/dev/null 2>&1; then
    groupadd -g "$gid" vmail
  fi
  if ! id -u "$user" >/dev/null 2>&1; then
    useradd -g "$gid" -u "$uid" -d "$home" -m -s /usr/sbin/nologin "$user"
  fi
}

function set_hostname() {
  if [[ $(hostname -f 2>/dev/null || true) != "$MAIL_HOSTNAME" ]]; then
    log_info "Setting hostname to $MAIL_HOSTNAME"
    hostnamectl set-hostname "$MAIL_HOSTNAME"
    # Ensure /etc/hosts contains an entry
    if ! grep -q "$MAIL_HOSTNAME" /etc/hosts; then
      local ip4
      ip4=$(hostname -I | awk '{print $1}')
      echo "$ip4 $MAIL_HOSTNAME ${MAIL_HOSTNAME%%.*}" >> /etc/hosts
    fi
  fi
}

########################################
# Begin installation
########################################

log_info "Updating apt cache and upgrading minimal packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates software-properties-common lsb-release gnupg2
apt-get upgrade -yq

set_hostname

log_info "Preseed Postfix debconf to avoid interactive prompts"
# Internet Site; system mail name = MAIL_DOMAIN
echo "postfix postfix/mailname string $MAIL_DOMAIN" | debconf-set-selections
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections

log_info "Installing core packages"
CORE_PKGS=(postfix postfix-pcre dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-sieve dovecot-managesieved opendkim opendkim-tools opendmarc)
EXTRA_PKGS=(openssl rsyslog logrotate cron)
apt_install "${CORE_PKGS[@]}" "${EXTRA_PKGS[@]}"

if [[ "$ENABLE_SPAMASSASSIN" == true ]]; then
  log_info "Installing SpamAssassin and spamass-milter"
  apt_install spamassassin spamc spamass-milter
fi

if [[ "$ENABLE_FAIL2BAN" == true ]]; then
  log_info "Installing Fail2ban"
  apt_install fail2ban
fi

if [[ "$USE_SELFSIGNED" == false ]]; then
  log_info "Installing Certbot (Let's Encrypt)"
  # Prefer snap for newer certbot on Ubuntu
  if ! command -v snap >/dev/null 2>&1; then
    apt_install snapd
  fi
  snap install core || true
  snap refresh core || true
  if snap list | grep -q certbot; then
    log_info "certbot snap already installed"
  else
    snap install --classic certbot
  fi
  ln -sf /snap/bin/certbot /usr/bin/certbot
fi

########################################
# TLS certificates
########################################
CERT_DIR="/etc/ssl/mail"
LE_KEY="/etc/letsencrypt/live/${MAIL_HOSTNAME}/privkey.pem"
LE_FULLCHAIN="/etc/letsencrypt/live/${MAIL_HOSTNAME}/fullchain.pem"
KEY_PATH="${CERT_DIR}/privkey.pem"
CERT_PATH="${CERT_DIR}/fullchain.pem"

mkdir -p "$CERT_DIR"

if [[ "$USE_SELFSIGNED" == false ]]; then
  log_info "Attempting Let's Encrypt certificate issuance for $MAIL_HOSTNAME"
  # Use standalone authenticator (requires ports 80/443 free)
  if systemctl is-active --quiet nginx; then systemctl stop nginx; fi || true
  if systemctl is-active --quiet apache2; then systemctl stop apache2; fi || true
  # Open port 80 temporarily if ufw enabled later
  certbot certonly --standalone --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL:-admin@${MAIL_DOMAIN}}" -d "$MAIL_HOSTNAME" || {
    log_warn "Let's Encrypt failed, falling back to self-signed certs"
    USE_SELFSIGNED=true
  }

  if [[ "$USE_SELFSIGNED" == false && -f "$LE_KEY" && -f "$LE_FULLCHAIN" ]]; then
    ln -sf "$LE_KEY" "$KEY_PATH"
    ln -sf "$LE_FULLCHAIN" "$CERT_PATH"
  fi
fi

if [[ "$USE_SELFSIGNED" == true ]]; then
  log_info "Generating self-signed certificate for $MAIL_HOSTNAME"
  openssl req -x509 -nodes -days 825 -newkey rsa:4096 \
    -keyout "$KEY_PATH" -out "$CERT_PATH" \
    -subj "/CN=$MAIL_HOSTNAME" \
    -addext "subjectAltName=DNS:$MAIL_HOSTNAME,DNS:$MAIL_DOMAIN" >/dev/null 2>&1
  chmod 600 "$KEY_PATH"
fi

########################################
# Create vmail user and directories
########################################

log_info "Creating vmail user and mailbox directory layout"
ensure_user_group "vmail" 5000 5000 "/var/mail/vhosts"
mkdir -p /var/mail/vhosts
chown -R vmail:vmail /var/mail/vhosts
chmod -R 770 /var/mail/vhosts

########################################
# Dovecot configuration
########################################

log_info "Configuring Dovecot"
backup_file /etc/dovecot/dovecot.conf
cat >/etc/dovecot/dovecot.conf <<'EOF'
!include_try /usr/share/dovecot/protocols.d/*.protocol
protocols = imap pop3 lmtp

dict {
}

!include conf.d/*.conf
!include_try local.conf
EOF

# 10-mail.conf
backup_file /etc/dovecot/conf.d/10-mail.conf
cat >/etc/dovecot/conf.d/10-mail.conf <<EOF
mail_location = maildir:/var/mail/vhosts/%d/%n/Maildir
mail_privileged_group = mail
first_valid_uid = 5000
last_valid_uid = 5000

namespace inbox {
  inbox = yes
}
EOF

# 10-auth.conf
backup_file /etc/dovecot/conf.d/10-auth.conf
cat >/etc/dovecot/conf.d/10-auth.conf <<'EOF'
disable_plaintext_auth = yes
auth_username_format = %n

passdb {
  driver = passwd-file
  args = scheme=SHA512-CRYPT username_format=%u /etc/dovecot/users
}

userdb {
  driver = static
  args = uid=5000 gid=5000 home=/var/mail/vhosts/%d/%n
}

auth_mechanisms = plain login
EOF

touch /etc/dovecot/users
chmod 640 /etc/dovecot/users
chown root:dovecot /etc/dovecot/users

# 10-master.conf (LMTP + auth socket)
backup_file /etc/dovecot/conf.d/10-master.conf
cat >/etc/dovecot/conf.d/10-master.conf <<'EOF'
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  user = dovecot
}

service imap-login {
  inet_listener imaps {
    port = 993
  }
  inet_listener imap {
    port = 143
  }
}

service pop3-login {
  inet_listener pop3s {
    port = 995
  }
  inet_listener pop3 {
    port = 110
  }
}
EOF

# 10-ssl.conf
backup_file /etc/dovecot/conf.d/10-ssl.conf
cat >/etc/dovecot/conf.d/10-ssl.conf <<EOF
ssl = required
ssl_cert = <${CERT_PATH}
ssl_key = <${KEY_PATH}
EOF

# IPv6 toggle for Dovecot (default supports both). No explicit setting needed.

########################################
# OpenDKIM configuration
########################################

log_info "Configuring OpenDKIM"
backup_file /etc/opendkim.conf
cat >/etc/opendkim.conf <<'EOF'
Syslog                  yes
UMask                   002
OversignHeaders         From
Canonicalization        relaxed/simple
Mode                    sv
SubDomains              no
AutoRestart             yes
AutoRestartRate         10/1h
Background              yes
DNSTimeout              5
SignatureAlgorithm      rsa-sha256

# Socket is configured via /etc/default/opendkim to work with Postfix chroot

# Key tables and signing
KeyTable               refile:/etc/opendkim/KeyTable
SigningTable           refile:/etc/opendkim/SigningTable
ExternalIgnoreList     refile:/etc/opendkim/TrustedHosts
InternalHosts          refile:/etc/opendkim/TrustedHosts
EOF

backup_file /etc/default/opendkim
cat >/etc/default/opendkim <<'EOF'
RUNDIR=/var/run/opendkim
SOCKET="local:/var/spool/postfix/opendkim/opendkim.sock"
USER=opendkim
GROUP=opendkim
MODE=0660
PIDFILE="$RUNDIR/opendkim.pid"
EXTRAAFTER=
EOF

mkdir -p /etc/opendkim/keys
mkdir -p /var/spool/postfix/opendkim
chown opendkim:opendkim /var/spool/postfix/opendkim
chmod 750 /var/spool/postfix/opendkim

cat >/etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
${MAIL_HOSTNAME}
*.${MAIL_DOMAIN}
${MAIL_DOMAIN}
EOF

cat >/etc/opendkim/SigningTable <<EOF
*@${MAIL_DOMAIN}    mail._domainkey.${MAIL_DOMAIN}
EOF

cat >/etc/opendkim/KeyTable <<EOF
mail._domainkey.${MAIL_DOMAIN} ${MAIL_DOMAIN}:mail:/etc/opendkim/keys/${MAIL_DOMAIN}/mail.private
EOF

# Generate DKIM key if missing
if [[ ! -f "/etc/opendkim/keys/${MAIL_DOMAIN}/mail.private" ]]; then
  mkdir -p "/etc/opendkim/keys/${MAIL_DOMAIN}"
  opendkim-genkey -r -s mail -d "$MAIL_DOMAIN" -D "/etc/opendkim/keys/${MAIL_DOMAIN}"
  chown -R opendkim:opendkim "/etc/opendkim/keys/${MAIL_DOMAIN}"
  chmod 700 "/etc/opendkim/keys/${MAIL_DOMAIN}"
  chmod 600 "/etc/opendkim/keys/${MAIL_DOMAIN}"/*
fi

########################################
# OpenDMARC configuration
########################################

log_info "Configuring OpenDMARC"
backup_file /etc/opendmarc.conf
cat >/etc/opendmarc.conf <<'EOF'
AuthservID          mailserver
TrustedAuthservIDs  mailserver,localhost
PidFile             /var/run/opendmarc/opendmarc.pid
UMask               002
Syslog              true
SyslogSuccess       true
Socket              inet:8893@localhost
UserID              opendmarc:opendmarc
SoftwareHeader      true
SPFIgnoreResults    false
EOF

########################################
# SpamAssassin + milter
########################################

if [[ "$ENABLE_SPAMASSASSIN" == true ]]; then
  log_info "Configuring SpamAssassin and spamass-milter"
  # Enable SpamAssassin service
  sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/spamassassin || true
  systemctl enable spamassassin

  backup_file /etc/default/spamass-milter
  cat >/etc/default/spamass-milter <<'EOF'
# Run as spamass-milter user; create socket for postfix chroot
OPTIONS="-u spamass-milter -i 127.0.0.1 -x"
SOCKET="/var/spool/postfix/spamass/spamass.sock"
EOF
  mkdir -p /var/spool/postfix/spamass
  chown spamass-milter:postfix /var/spool/postfix/spamass
  chmod 750 /var/spool/postfix/spamass
fi

########################################
# Postfix configuration
########################################

log_info "Configuring Postfix"
backup_file /etc/postfix/main.cf
backup_file /etc/postfix/master.cf

# main.cf
cat >/etc/postfix/main.cf <<EOF
smtputf8_enable = no
compatibility_level = 2

myhostname = ${MAIL_HOSTNAME}
mydomain = ${MAIL_DOMAIN}
myorigin = \\$mydomain
mydestination = localhost

# Network
inet_interfaces = all
inet_protocols = ${ENABLE_IPV6:true?all:ipv4}

# Relay and restrictions (no open relay)
smtpd_recipient_restrictions = \
    permit_mynetworks, \
    permit_sasl_authenticated, \
    reject_unauth_destination

# TLS settings
smtpd_tls_cert_file = ${CERT_PATH}
smtpd_tls_key_file = ${KEY_PATH}
smtpd_use_tls = yes
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtpd_tls_auth_only = yes

# SASL via Dovecot
authentication with Dovecot
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
broken_sasl_auth_clients = yes

# Virtual domains and mailboxes
virtual_mailbox_domains = ${MAIL_DOMAIN}
virtual_transport = lmtp:unix:private/dovecot-lmtp

# Milter integration
milter_default_action = accept
milter_protocol = 6
EOF

# Append milters
if [[ "$ENABLE_SPAMASSASSIN" == true ]]; then
  echo "smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock, inet:localhost:8893, unix:/var/spool/postfix/spamass/spamass.sock" >> /etc/postfix/main.cf
  echo "non_smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock, inet:localhost:8893, unix:/var/spool/postfix/spamass/spamass.sock" >> /etc/postfix/main.cf
else
  echo "smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock, inet:localhost:8893" >> /etc/postfix/main.cf
  echo "non_smtpd_milters = unix:/var/spool/postfix/opendkim/opendkim.sock, inet:localhost:8893" >> /etc/postfix/main.cf
fi

# master.cf (submission/smtps with enforced TLS and SASL)
cat >/etc/postfix/master.cf <<'EOF'
smtp      inet  n       -       y       -       -       smtpd
  -o smtpd_tls_security_level=may
  -o smtpd_sasl_auth_enable=no
  -o smtpd_client_restrictions=

submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       -       1000    tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
  -o syslog_name=postfix/$service_name
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
EOF

########################################
# UFW firewall
########################################

if [[ "$ENABLE_UFW" == true ]]; then
  log_info "Configuring UFW firewall rules"
  if ! command -v ufw >/dev/null 2>&1; then
    apt_install ufw
  fi
  ufw allow 22/tcp || true
  ufw allow 25/tcp || true
  ufw allow 465/tcp || true
  ufw allow 587/tcp || true
  ufw allow 110/tcp || true
  ufw allow 995/tcp || true
  ufw allow 143/tcp || true
  ufw allow 993/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  yes | ufw enable || true
fi

########################################
# Fail2ban
########################################

if [[ "$ENABLE_FAIL2BAN" == true ]]; then
  log_info "Configuring Fail2ban for Postfix/Dovecot"
  backup_file /etc/fail2ban/jail.local
  cat >/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
maxretry = 6
bantime = 1h
findtime = 10m

[postfix]
enabled = true

[postfix-sasl]
enabled = true

[dovecot]
enabled = true
EOF
fi

########################################
# Systemd: enable and restart services
########################################

log_info "Enabling and restarting services"
systemctl daemon-reload || true
systemctl enable postfix dovecot opendkim opendmarc || true
systemctl restart opendkim || true
systemctl restart opendmarc || true
if [[ "$ENABLE_SPAMASSASSIN" == true ]]; then
  systemctl enable spamass-milter || true
  systemctl restart spamassassin || true
  systemctl restart spamass-milter || true
fi
systemctl restart dovecot || true
systemctl restart postfix || true

########################################
# Helper utilities for user management
########################################

log_info "Installing helper commands: add-mail-user, del-mail-user, list-mail-users"

cat >/usr/local/sbin/add-mail-user <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo "Run as root" >&2; exit 1; fi
if [[ $# -lt 2 ]]; then echo "Usage: add-mail-user user@domain password" >&2; exit 1; fi
USER_EMAIL="$1"
USER_PASS="$2"
DOMAIN="${USER_EMAIL#*@}"
USER="${USER_EMAIL%@*}"
if ! command -v doveadm >/dev/null 2>&1; then echo "doveadm not found" >&2; exit 1; fi
HASH=$(doveadm pw -s SHA512-CRYPT -p "$USER_PASS")
LINE="${USER_EMAIL}:${HASH}::::::"
if grep -q "^${USER_EMAIL}:" /etc/dovecot/users; then
  sed -i "s|^${USER_EMAIL}:.*|${LINE}|" /etc/dovecot/users
else
  echo "$LINE" >> /etc/dovecot/users
fi
MAILDIR="/var/mail/vhosts/${DOMAIN}/${USER}/Maildir"
install -d -m 700 -o 5000 -g 5000 "$MAILDIR"/{cur,new,tmp} || true
systemctl reload dovecot || true
echo "Created/updated mailbox for ${USER_EMAIL}"
EOF
chmod +x /usr/local/sbin/add-mail-user

cat >/usr/local/sbin/del-mail-user <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo "Run as root" >&2; exit 1; fi
if [[ $# -lt 1 ]]; then echo "Usage: del-mail-user user@domain [--keep-mail]" >&2; exit 1; fi
USER_EMAIL="$1"
KEEP=false
if [[ "${2:-}" == "--keep-mail" ]]; then KEEP=true; fi
DOMAIN="${USER_EMAIL#*@}"
USER="${USER_EMAIL%@*}"
if grep -q "^${USER_EMAIL}:" /etc/dovecot/users; then
  sed -i "/^${USER_EMAIL}:/d" /etc/dovecot/users
fi
MAILHOME="/var/mail/vhosts/${DOMAIN}/${USER}"
if [[ "$KEEP" != true ]]; then
  rm -rf "$MAILHOME"
fi
systemctl reload dovecot || true
echo "Removed user ${USER_EMAIL} (mail kept: $KEEP)"
EOF
chmod +x /usr/local/sbin/del-mail-user

cat >/usr/local/sbin/list-mail-users <<'EOF'
#!/usr/bin/env bash
if [[ -f /etc/dovecot/users ]]; then
  cut -d: -f1 /etc/dovecot/users
fi
EOF
chmod +x /usr/local/sbin/list-mail-users

########################################
# Seed a postmaster account
########################################

POSTMASTER_EMAIL="postmaster@${MAIL_DOMAIN}"
DEFAULT_POSTMASTER_PASS=$(tr -dc 'A-Za-z0-9!@#%^*_' </dev/urandom | head -c 16 || true)
/usr/local/sbin/add-mail-user "$POSTMASTER_EMAIL" "$DEFAULT_POSTMASTER_PASS" || true

########################################
# Print DNS guidance
########################################

log_info "Gathering DKIM public key"
DKIM_SELECTOR="mail"
DKIM_PUBFILE="/etc/opendkim/keys/${MAIL_DOMAIN}/mail.txt"
DKIM_VALUE=""
if [[ -f "$DKIM_PUBFILE" ]]; then
  DKIM_VALUE=$(sed -n 's/.*(\"\(.*\)\").*/\1/p' "$DKIM_PUBFILE" | tr -d '\n')
  if [[ -z "$DKIM_VALUE" ]]; then
    DKIM_VALUE=$(tr -d '\n' <"$DKIM_PUBFILE" | sed -e 's/.*p=\([A-Za-z0-9+/=]*\).*/\1/')
  fi
fi

SERVER_IP4=$(curl -4 -s https://api.ipify.org || hostname -I | awk '{print $1}') || true
SERVER_IP6=$(curl -6 -s https://api64.ipify.org || true)

cat <<EOF

============================================================
Mail server setup complete.

Host:   ${MAIL_HOSTNAME}
Domain: ${MAIL_DOMAIN}

Postmaster seeded account:
  Email:    ${POSTMASTER_EMAIL}
  Password: ${DEFAULT_POSTMASTER_PASS}

Open these ports in your security group/firewall if needed:
  25, 465, 587 (SMTP), 993/143 (IMAP/IMAPS), 995/110 (POP3/POP3S), 80/443 (for Let's Encrypt)

Add the following DNS records at your DNS provider:

- A: ${MAIL_HOSTNAME} -> ${SERVER_IP4}
EOF
if [[ -n "$SERVER_IP6" ]]; then
  echo "- AAAA: ${MAIL_HOSTNAME} -> ${SERVER_IP6}"
fi
cat <<EOF
- MX: ${MAIL_DOMAIN} -> ${MAIL_HOSTNAME} (priority 10)
- TXT (SPF) for ${MAIL_DOMAIN}: "v=spf1 mx a -all"
- TXT (DMARC) for _dmarc.${MAIL_DOMAIN}: "v=DMARC1; p=quarantine; rua=mailto:dmarc@${MAIL_DOMAIN}; ruf=mailto:dmarc@${MAIL_DOMAIN}; fo=1"
- TXT (DKIM) for ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}:

EOF
if [[ -f "$DKIM_PUBFILE" ]]; then
  cat "$DKIM_PUBFILE"
else
  echo "  (DKIM record file not found; check /etc/opendkim/keys/${MAIL_DOMAIN}/)"
fi

cat <<'EOF'

Manage users:
  sudo add-mail-user user@domain 'Password'
  sudo del-mail-user user@domain [--keep-mail]
  sudo list-mail-users

Test:
  - From a client (Thunderbird/Outlook):
    Incoming IMAP: host=mail.domain, port=993, SSL/TLS, auth=normal password
    Outgoing SMTP Submission: host=mail.domain, port=587, STARTTLS, auth=normal password

Logs:
  journalctl -u postfix -f
  journalctl -u dovecot -f
  journalctl -u opendkim -u opendmarc -f
EOF

log_info "All done. Please configure DNS and wait for propagation before sending mail."