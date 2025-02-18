#!/bin/bash

rm /var/log/samba-setup.log
echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de l'installation et de la configuration" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Mise à jour et installation des paquets nécessaires
echo "$(date '+%Y-%m-%d %H:%M:%S') - Mise à jour et installation des paquets nécessaires..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
apt update && apt upgrade -y | tee -a /var/log/samba-setup.log
apt install -y samba-ad-dc krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban sudo ufw krb5-admin-server dnsutils iptables openssh-server libpam-tmpdir apt-listbugs needrestart debsums apt-show-versions rkhunter chkrootkit chrony aide logwatch libpam-winbind libnss-winbind sssd | tee -a /var/log/samba-setup.log

# Vérification de l'installation des paquets
for pkg in samba-ad-dc krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban ufw krb5-admin-server sudo dnsutils iptables openssh-server libpam-tmpdir apt-listbugs needrestart debsums apt-show-versions rkhunter chkrootkit chrony aide logwatch libpam-winbind libnss-winbind sssd; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Le paquet $pkg n'a pas été installé !" | tee -a /var/log/samba-setup.log
        echo "====================" | tee -a /var/log/samba-setup.log
        exit 1
    fi
done
echo "$(date '+%Y-%m-%d %H:%M:%S') - Tous les paquets ont été installés avec succès !" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Configuration GRUB avec mot de passe
echo "[*] Configuration de GRUB avec mot de passe..." | tee -a /var/log/samba-setup.log
GRUB_PASSWORD="N@rthSt@r33<:"
HASHED_PASSWORD=$(echo -e "$GRUB_PASSWORD\n$GRUB_PASSWORD" | grub-mkpasswd-pbkdf2 | grep -oP 'grub.pbkdf2.sha512.*')

if [ -n "$HASHED_PASSWORD" ]; then
    echo -e "set superusers=\"root\"\npassword_pbkdf2 root $HASHED_PASSWORD" > /etc/grub.d/40_custom
    update-grub | tee -a $LOG_FILE
    echo "[*] GRUB configuré avec succès." | tee -a /var/log/samba-setup.log
	echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "[!] Erreur : Impossible de générer le hash du mot de passe GRUB !" | tee -a /var/log/samba-setup.log
	echo "====================" | tee -a /var/log/samba-setup.log
fi

# Renforcement des permissions des fichiers système sensibles
echo "[*] Renforcement des permissions des fichiers critiques..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
chown root:root /etc/passwd /etc/shadow /etc/group /etc/gshadow
chmod 600 /etc/shadow /etc/gshadow
chmod 644 /etc/passwd /etc/group

# Sécurisation des partitions
echo "[*] Sécurisation des partitions (/tmp, /var)..." | tee -a tee -a /var/log/samba-setup.log
FSTAB_UPDATED=false
if ! grep -q "/tmp" /etc/fstab; then
    echo "/tmp    /tmp    tmpfs   defaults,noexec,nosuid,nodev  0 0" >> /etc/fstab
    FSTAB_UPDATED=true
fi
if ! grep -q "/var" /etc/fstab; then
    echo "/var    /var    tmpfs   defaults,noexec,nosuid,nodev  0 0" >> /etc/fstab
    FSTAB_UPDATED=true
fi

if $FSTAB_UPDATED; then
    systemctl daemon-reexec
    mount -a
    echo "[*] Partitions sécurisées et montées." | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "[*] Aucune modification nécessaire pour les partitions." | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
fi

# Configuration PAM pour renforcer les mots de passe
echo "[*] Configuration de PAM pour renforcer les mots de passe..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
PAM_CONFIG="/etc/security/pwquality.conf"
sed -i '/^minlen/d' $PAM_CONFIG
sed -i '/^minclass/d' $PAM_CONFIG
sed -i '/^retry/d' $PAM_CONFIG
echo "minlen = 14" >> $PAM_CONFIG
echo "minclass = 4" >> $PAM_CONFIG
echo "retry = 3" >> $PAM_CONFIG

# Renforcement des paramètres sysctl
echo "[*] Renforcement des paramètres sysctl..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
SYSCTL_CONFIG="/etc/sysctl.d/99-hardening.conf"
cat <<EOF > $SYSCTL_CONFIG
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
EOF
sysctl --system | tee -a tee -a /var/log/samba-setup.log

# Désactivation des protocoles réseau inutilisés
echo "[*] Désactivation des protocoles réseau inutilisés..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
for module in dccp sctp rds tipc; do
    if lsmod | grep -q "$module"; then
        modprobe -r "$module"
        echo "[*] Module $module désactivé." | tee -a /var/log/samba-setup.log
    else
        echo "[*] Module $module déjà désactivé." | tee -a /var/log/samba-setup.log
    fi
done

# Installation et configuration de chrony
echo "[*] Configuration de Chrony pour la synchronisation de l’heure..." | tee -a /var/log/samba-setup.log

# Vérifier si Chrony est installé, sinon l'installer
if ! command -v chronyc &> /dev/null; then
    echo "[!] Chrony n'est pas installé. Installation en cours..." | tee -a /var/log/samba-setup.log
    apt update && apt install -y chrony | tee -a /var/log/samba-setup.log
fi

# Écrire la configuration directement dans /etc/chrony/chrony.conf
echo "[*] Mise à jour de la configuration Chrony..." | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/chrony/chrony.conf
server ntp.obspm.fr iburst
server ntp.laas.fr iburst
server ntp.ciril.fr iburst
server ntp.univ-lyon1.fr iburst
server ntp.ens.fr iburst

driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
maxsources 5
rtcsync
allow all

logdir /var/log/chrony
EOF

echo "[*] Fichier de configuration Chrony mis à jour." | tee -a /var/log/samba-setup.log

# Redémarrage et Activation de Chrony pour appliquer la nouvelle configuration
echo "[*] Redémarrage de Chrony..." | tee -a /var/log/samba-setup.log
systemctl restart chrony && systemctl enable chrony | tee -a /var/log/samba-setup.log


# Vérifier si Chrony fonctionne bien
if systemctl is-active --quiet chrony; then
    echo "[*] Chrony est actif et fonctionne correctement." | tee -a /var/log/samba-setup.log
else
    echo "[!] Erreur : Chrony ne s'est pas lancé correctement." | tee -a /var/log/samba-setup.log
    systemctl status chrony | tee -a /var/log/samba-setup.log
fi

# Vérifier la synchronisation NTP
echo "[*] Vérification de la synchronisation NTP..." | tee -a /var/log/samba-setup.log
chronyc sources -v | tee -a /var/log/samba-setup.log

echo "[*] Configuration de Chrony terminée." | tee -a /var/log/samba-setup.log

# Activation des rapports logwatch
echo "[*] Configuration de logwatch..." | tee -a tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
if [ -f /usr/sbin/logwatch ]; then
    logwatch --detail high --mailto root --range today | tee -a /var/log/samba-setup.log
else
    echo "[!] Logwatch n'est pas installé. Exécution ignorée." | tee -a /var/log/samba-setup.log
fi

# Vérification des rootkits
echo "[*] Analyse du système pour détecter des rootkits..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Correction pour RKHunter : s'assurer que le répertoire temporaire existe
mkdir -p /var/lib/rkhunter/tmp
chmod 750 /var/lib/rkhunter/tmp

rkhunter --update | tee -a /var/log/samba-setup.log
rkhunter --checkall | tee -a /var/log/samba-setup.log

echo "[*] Lancement de chkrootkit..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
chkrootkit | | tee -a /var/log/samba-setup.log


# Configuration de Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Kerberos avec des options renforcées..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF >/etc/krb5.conf
[libdefaults]
    default_realm = NORTHSTAR.COM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    forwardable = true
    renewable = true
    rdns = false
    ticket_lifetime = 10h
    renew_lifetime = 7d
    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    permitted_enctypes = aes256-cts aes128-cts
EOF

# Vérification de la configuration Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de la configuration Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

ERROR_LOG=$(samba-tool testparm 2>&1 | grep -E 'ERROR|WARNING')

if [ -n "$ERROR_LOG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème détecté dans la configuration Samba !" | tee -a /var/log/samba-setup.log
    echo "Détails de l'erreur :" | tee -a /var/log/samba-setup.log
    echo "$ERROR_LOG" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration Samba valide." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Arrêt et désactivation des services non nécessaires
echo "$(date '+%Y-%m-%d %H:%M:%S') - Arrêt et désactivation des services smbd, nmbd et winbind..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc

# Configuration du contrôleur de domaine Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression du fichier de configuration par défaut s'il existe." | tee -a /var/log/samba-setup.log
if [ -f /etc/samba/smb.conf ]; then
    rm /etc/samba/smb.conf
fi

export SAMBA_ADMIN_PASS='@fterTheB@ll33/'
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration du contrôleur de domaine Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass="$SAMBA_ADMIN_PASS" --server-role=dc | tee -a /var/log/samba-setup.log

# Vérification du succès du provisionnement
if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Échec du provisionnement Samba !" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Génération de l'Autorité de Certification (CA) et des certificats TLS
echo "$(date '+%Y-%m-%d %H:%M:%S') - Génération de l'Autorité de Certification (CA) et des certificats TLS..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
mkdir -p /etc/samba/private
chmod 700 /etc/samba/private

# 1. Clé privée pour l'autorité de certification (CA)
openssl genrsa -out /etc/samba/private/tls-ca.key 2048
# 2. Certificat de l'autorité de certification (CA)
openssl req -x509 -new -nodes -key /etc/samba/private/tls-ca.key -sha256 -days 3650 \
    -out /etc/samba/private/tls-ca.crt -subj "/C=FR/ST=Paris/L=Paris/O=Northstar CA/OU=IT Department/CN=Northstar Root CA"

# 3. Clé privée et CSR pour Samba
openssl genrsa -out /etc/samba/private/tls.key 2048
openssl req -new -key /etc/samba/private/tls.key -out /etc/samba/private/tls.csr -subj "/CN=NORTHSTAR.COM"

# 4. Signer le certificat de Samba avec le CA
openssl x509 -req -in /etc/samba/private/tls.csr -CA /etc/samba/private/tls-ca.crt -CAkey /etc/samba/private/tls-ca.key \
    -CAcreateserial -out /etc/samba/private/tls.crt -days 365 -sha256

# Protection des certificats TLS
chmod 600 /etc/samba/private/tls.*

echo "$(date '+%Y-%m-%d %H:%M:%S') - Certificats TLS générés et protégés." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Configuration avancée pour Samba (ajout d'options au smb.conf)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Durcissement des configurations Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF >>/etc/samba/smb.conf
[global]
    tls enabled = yes
    tls keyfile = /etc/samba/private/tls.key
    tls certfile = /etc/samba/private/tls.crt
    tls cafile = /etc/samba/private/tls-ca.crt
    ntlm auth = mschapv2-and-ntlmv2-only
    server min protocol = SMB2
    server max protocol = SMB3
    smb encrypt = required
    disable netbios = yes
    dns forwarder = 8.8.8.8
    restrict anonymous = 2
    ldap server require strong auth = yes
    log level = 3
    log file = /var/log/samba/log.%m
    max log size = 5000
    ldap timeout = 15a
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    max smbd processes = 500
    allow unsafe cluster upgrade = no
    clustering = no

[sysvol]
    path = /var/lib/samba/sysvol
    read only = no
EOF

# Redémarrage et vérification des services Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage des services Samba..." | tee -a /var/log/samba-setup.log
systemctl restart samba-ad-dc

if systemctl status samba-ad-dc | grep -q "active (running)"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Samba est démarré avec succès." | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Samba ne s'est pas démarré correctement." | tee -a /var/log/samba-setup.log
    exit 1
fi


# Téléchargement et installation de osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Téléchargement et installation de osquery..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
wget https://pkg.osquery.io/deb/osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
dpkg -i osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
systemctl restart osqueryd | tee -a /var/log/samba-setup.log

# Configuration d'osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration d'osquery..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/osquery/osquery.conf
{
    "options": {
        "logger_plugin": "filesystem",
        "logger_path": "/var/log/osquery",
        "disable_events": "false",
        "schedule_splay_percent": "10"
    },
    "schedule": {
        "kerberos_audit": {
            "query": "SELECT * FROM processes WHERE name LIKE '%krb%';",
            "interval": 60
        },
        "file_events": {
            "query": "SELECT * FROM file WHERE path LIKE '/etc/%' OR path LIKE '/var/lib/samba/private/%';",
            "interval": 60
        },
        "ssh_audit": {
            "query": "SELECT * FROM process_open_sockets WHERE family = '2' AND remote_address IS NOT NULL;",
            "interval": 60
        }
    }
}
EOF

systemctl enable osqueryd
systemctl restart osqueryd
if systemctl is-active --quiet osqueryd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - osqueryd fonctionne !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : osqueryd n'a pas démarré !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi
echo "====================" | tee -a /var/log/samba-setup.log



echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de la sécurisation de SSH..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Vérification de l'installation d'OpenSSH Server
if ! dpkg -l | grep -qw openssh-server; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OpenSSH Server n'est pas installé. Installation en cours..." | tee -a /var/log/samba-setup.log
    apt update && apt install -y openssh-server libpam-winbind libnss-winbind sssd | tee -a /var/log/samba-setup.log
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OpenSSH Server installé avec succès." | tee -a /var/log/samba-setup.log
fi

# Vérification de l'existence du fichier de configuration SSH
SSH_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSH_CONFIG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de $SSH_CONFIG..." | tee -a /var/log/samba-setup.log

    # Modifications de la configuration SSH pour sécurisation
    sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
    sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    sed -i 's/#\?X11Forwarding.*/X11Forwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?AllowTcpForwarding.*/AllowTcpForwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSH_CONFIG"
    sed -i 's/#\?Compression.*/Compression no/' "$SSH_CONFIG"

    # Ajout de la directive AllowGroups pour limiter l'accès SSH au groupe Samba NORTHSTAR\Group_ADMT0
    if grep -q "^AllowUsers" "$SSH_CONFIG"; then
        sed -i '/^AllowUsers/d' "$SSH_CONFIG"
    fi
    if grep -q "^AllowGroups" "$SSH_CONFIG"; then
        sed -i 's/^AllowGroups.*/AllowGroups NORTHSTAR\\Group_ADMT0/' "$SSH_CONFIG"
    else
        echo "AllowGroups NORTHSTAR\\Group_ADMT0" >> "$SSH_CONFIG"
    fi

    # Redémarrage du service SSH
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage du service SSH..." | tee -a /var/log/samba-setup.log
    systemctl restart sshd

    # Vérification du statut du service
    if systemctl is-active --quiet sshd; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - SSH est sécurisé et fonctionne !" | tee -a /var/log/samba-setup.log
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : SSH n'a pas redémarré correctement !" | tee -a /var/log/samba-setup.log
        exit 1
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Fichier $SSH_CONFIG non trouvé !" | tee -a /var/log/samba-setup.log
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Sécurisation de SSH terminée." | tee -a /var/log/samba-setup.log



# Configuration de Fail2Ban pour Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Fail2Ban pour Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Création de la configuration spécifique pour Samba
cat <<EOF > /etc/fail2ban/jail.d/samba.conf
[samba]
enabled = true
filter = samba
action = iptables-multiport[name=Samba, port="139,445", protocol=tcp]
logpath = /var/log/samba/log.smbd
maxretry = 3
bantime = 600
findtime = 600
EOF

# Vérification et création du fichier de filtre pour Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification du fichier de filtre pour Samba..." | tee -a /var/log/samba-setup.log
if [ ! -f /etc/fail2ban/filter.d/samba.conf ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Fichier de filtre manquant, création du fichier..." | tee -a /var/log/samba-setup.log
    cat <<EOF > /etc/fail2ban/filter.d/samba.conf
# Fail2Ban filter for Samba
[Definition]
failregex = .*smbd.*authentication.*failed.*
ignoreregex =
EOF
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Fichier de filtre déjà présent." | tee -a /var/log/samba-setup.log
fi

# Vérification du socket Fail2Ban
if [ -S /var/run/fail2ban/fail2ban.sock ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression du fichier de socket existant..." | tee -a /var/log/samba-setup.log
    rm -f /var/run/fail2ban/fail2ban.sock
fi

# Redémarrage de Fail2Ban
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage de Fail2Ban..." | tee -a /var/log/samba-setup.log
systemctl restart fail2ban

# Vérification du statut de Fail2Ban
if systemctl is-active --quiet fail2ban; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Fail2Ban fonctionne !" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Fail2Ban n'a pas démarré !" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Vérification des prisons Fail2Ban
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification des prisons Fail2Ban..." | tee -a /var/log/samba-setup.log
fail2ban-client status samba | tee -a /var/log/samba-setup.log || echo " Impossible de vérifier la prison Samba." | tee -a /var/log/samba-setup.log

echo "====================" | tee -a /var/log/samba-setup.log


# Configuration d'auditd pour surveiller Samba et Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration d'auditd..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/audit/rules.d/audit.rules
-w /etc/ -p wa -k etc-changes
-w /var/log/samba/ -p wa -k samba-logs
-w /var/log/audit/ -p wa -k audit-logs
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets
-a always,exit -F arch=b64 -S execve -F euid=0 -k root-commands
EOF

systemctl restart auditd
if systemctl is-active --quiet auditd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - auditd fonctionne et surveille Samba et Kerberos !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : auditd n'a pas redémarré !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi
echo "====================" | tee -a /var/log/samba-setup.log

# Exécution de Lynis pour l'audit du système
echo "$(date '+%Y-%m-%d %H:%M:%S') - Exécution de Lynis pour l'audit du système..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
lynis audit system | tee -a /var/log/lynis-audit.log

# Vérification de la configuration de Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Récupération de l'adresse IP de la machine et exécution de samba-tool domain info
samba-tool domain info $(hostname -I | awk '{print $1}') | tee -a /var/log/samba-setup.log

# Vérification du résultat de la commande précédente
if [ $? -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Samba fonctionne correctement." | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème détecté avec Samba !" | tee -a /var/log/samba-setup.log
    exit 1
fi
echo "====================" | tee -a /var/log/samba-setup.log


# Fin de l’installation et de la configuration du domaine et du serveur
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation de Samba et configuration du domaine terminée ! " | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Début de la configuration des groupes et utilisateurs
echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration des utilisateurs, groupes, politiques de mot de passe, unités d'organisation (OU) et GPO..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration des utilisateurs, groupes, politiques de mot de passe, unités d'organisation (OU) et GPO..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Création des groupes selon le modèle Tiering
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des groupes selon le modèle Tiering..." | tee -a $LOG_FILE
samba-tool group add Group_ADMT0 | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT1 | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT2 | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Création des unités d'organisation (OU)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création de l'OU parent NS..." | tee -a /var/log/samba-setup.log
samba-tool ou create "OU=NS,DC=northstar,DC=com" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

OU_LIST=(
    "OU=NS,OU=Group_ADMT0,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT1,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT2,DC=northstar,DC=com"
    "OU=NS,OU=Servers_T1,DC=northstar,DC=com"
    "OU=NS,OU=AdminWorkstations,DC=northstar,DC=com"
)

for OU in "${OU_LIST[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de l'existence de $OU..." | tee -a /var/log/samba-setup.log
    samba-tool ou list | grep -q "$(echo $OU | cut -d',' -f1 | cut -d'=' -f2)"
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - L'OU $OU existe déjà." | tee -a /var/log/samba-setup.log
        echo "====================" | tee -a /var/log/samba-setup.log
    else
        echo "$date - Création de l'OU $OU..." | tee -a /var/log/samba-setup.log
        echo "====================" | tee -a /var/log/samba-setup.log
        samba-tool ou create "$OU" | tee -a /var/log/samba-setup.log
    fi
    echo "====================" | tee -a /var/log/samba-setup.log
done

# Création des utilisateurs et attributions aux groupes
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des utilisateurs et attribution aux groupes..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

PASSWORD_HUGO=$(openssl rand -base64 16)
samba-tool user create Hugo_ADMT0 "$PASSWORD_HUGO" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT0 Hugo_ADMT0 | tee -a /var/log/samba-setup.log
echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur Hugo_ADMT0 créé avec mot de passe généré." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

PASSWORD_VOLTAIRE=$(openssl rand -base64 16)
samba-tool user create Voltaire_ADMT1 "$PASSWORD_VOLTAIRE" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT1 Voltaire_ADMT1 | tee -a /var/log/samba-setup.log
echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur Voltaire_ADMT1 créé avec mot de passe généré." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

PASSWORD_CLEMENCEAU=$(openssl rand -base64 16)
samba-tool user create Clemenceau_ADMT2 "$PASSWORD_CLEMENCEAU" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT2 Clemenceau_ADMT2 | tee -a /var/log/samba-setup.log
echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur Clemenceau_ADMT2 créé avec mot de passe généré." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Sauvegarde des mots de passe générés
echo "$date - Sauvegarde des mots de passe générés..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
echo "Hugo_ADMT0 : $PASSWORD_HUGO" >> /root/northstar_users.txt
echo "Voltaire_ADMT1 : $PASSWORD_VOLTAIRE" >> /root/northstar_users.txt
echo "Clemenceau_ADMT2 : $PASSWORD_CLEMENCEAU" >> /root/northstar_users.txt
chmod 600 /root/northstar_users.txt
echo "$(date '+%Y-%m-%d %H:%M:%S') - Mots de passe des utilisateurs sauvegardés dans /root/northstar_users.txt." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log


# Application des politiques de mots de passe sécurisées
echo "$(date '+%Y-%m-%d %H:%M:%S') - Application des politiques de mots de passe sécurisées..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-age=1
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --min-pwd-length=14
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=30
samba-tool domain passwordsettings set --reset-account-lockout-after=15

# Désactivation des comptes inutilisés
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des comptes inutilisés..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

if samba-tool user show guest > /dev/null 2>&1; then
    samba-tool user disable guest | tee -a /var/log/samba-setup.log
    samba-tool user setpassword guest --random | tee -a /var/log/samba-setup.log
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Compte 'guest' désactivé avec succès." | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Compte 'guest' introuvable ou déjà désactivé." | tee -a /var/log/samba-setup.log
fi
echo "====================" | tee -a /var/log/samba-setup.log

# Désactivation des groupes inutiles
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des groupes inutiles..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

GROUPS_TO_DISABLE=(
    "Guests"
    "Domain Guests"
    "Print Operators"
    "Backup Operators"
    "IIS_IUSRS"
)

for GROUP in "${GROUPS_TO_DISABLE[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Traitement du groupe '$GROUP'..." | tee -a /var/log/samba-setup.log
    if samba-tool group show "$GROUP" > /dev/null 2>&1; then
        MEMBERS=$(samba-tool group listmembers "$GROUP" 2>/dev/null)
        if [ -z "$MEMBERS" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Le groupe '$GROUP' est déjà vide." | tee -a /var/log/samba-setup.log
        else
            for MEMBER in $MEMBERS; do
                samba-tool group removemembers "$GROUP" "$MEMBER" | tee -a /var/log/samba-setup.log
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Membre '$MEMBER' supprimé du groupe '$GROUP'." | tee -a /var/log/samba-setup.log
            done
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Le groupe '$GROUP' n'existe pas." | tee -a /var/log/samba-setup.log
    fi
    echo "====================" | tee -a /var/log/samba-setup.log
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration terminée avec succès !" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Nettoyage final
echo "[*] Nettoyage des paquets obsolètes..."
apt autoremove -y
apt autoclean -y

echo "$(date '+%Y-%m-%d %H:%M:%S') - Fin de la Configuration" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
