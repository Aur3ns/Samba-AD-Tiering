#!/bin/bash

GPO_NAME="Restrict_T1"
DOMAIN="northstar.com"
OU_PATH="OU=Group_ADMT1,DC=northstar,DC=com"

echo "📌 Création de la GPO $GPO_NAME..."
samba-tool gpo create "$GPO_NAME"

GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

echo "🔒 Restriction des accès pour Group_ADMT1..."
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT1
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT1
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT1
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Group_ADMT1..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

echo " Ajout des groupes aux tiers en cours..."
samba-tool group addmembers "Remote Desktop Users" "Group_ADMT1"
samba-tool group addmembers "Server Operators" "Group_ADMT1"
samba-tool group addmembers "DnsAdmins" "Group_ADMT1"
samba-tool group addmembers "Group Policy Creator Owners" "Group_ADMT1"
samba-tool group addmembers "Event Log Readers" "Group_ADMT1"
samba-tool group addmembers "Network Configuration Operators" "Group_ADMT1"
samba-tool group addmembers "Performance Monitor Users" "Group_ADMT1"
samba-tool group addmembers "Performance Log Users" "Group_ADMT1"

echo "Fin de la Configuration"
