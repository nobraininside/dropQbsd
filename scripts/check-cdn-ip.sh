#!/bin/sh

# script per verificare se l'IP di cdn.openbsd.org registrato in /etc/hosts è variato
# da salvare in /usr/local/bin

# File dove salviamo l'ultimo IP conosciuto
IPFILE="/var/db/cdn.openbsd.ip"
DOMAIN="cdn.openbsd.org"

# Ottieni IP attuale tramite DNS
CURRENT_IP=$(dig +short "$DOMAIN" | grep -E '^[0-9.]+$' | head -n 1)

# Se IP non risolto, esci
[ -z "$CURRENT_IP" ] && exit 1

# Se il file non esiste, crealo con IP attuale
if [ ! -f "$IPFILE" ]; then
    echo "$CURRENT_IP" > "$IPFILE"
    exit 0
fi

# Carica IP precedente
OLD_IP=$(cat "$IPFILE")

# Confronta IP
if [ "$CURRENT_IP" != "$OLD_IP" ]; then
    echo "⚠️  IP di $DOMAIN cambiato: $OLD_IP → $CURRENT_IP"
    echo "$CURRENT_IP" > "$IPFILE"

    # Puoi aggiungere una notifica qui: es. mail, log, ecc.
    logger -t ip-monitor "IP di $DOMAIN cambiato: $OLD_IP → $CURRENT_IP"
fi
