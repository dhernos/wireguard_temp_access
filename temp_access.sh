#!/bin/bash

# --- SICHERHEITSCHECK UND VAR-SETUP ---
if [ "$EUID" -ne 0 ]; then
    echo "⚠️ Dieses Skript muss als root oder mit sudo ausgeführt werden."
    exit 1
fi

# Erforderliche Tools prüfen (wg, qrencode, at)
if ! command -v wg &> /dev/null; then
    echo "⚠️ Tool 'wg' wurde nicht gefunden. Bitte installieren."
    exit 1
fi

if ! command -V qrencode &> /dev/null; then
    echo "⚠️ Tool 'qrencode' wurde nicht gefunden. Bitte installieren."
    exit 1
fi

if ! command -V at &> /dev/null; then
    echo "⚠️ Tool''at' wurde nicht gefunden. Bitte installieren."
    exit 1
fi


# --- IP-GENERIERUNG BASIEREND AUF AKTUELLEM ZEITSTEMPEL ---
HOUR=$(printf "%d" $(date +%H))
MINUTE=$(printf "%d" $(date +%M))

# Generiere die Client-IP im 10.2.0.0/16 Netz basierend auf H:M
# Wir verwenden hier die tatsächlichen Werte (0-23 und 0-59)
CLIENT_IP="10.2.$HOUR.$MINUTE"

# --- SERVER-PARAMETER (BITTE ANPASSEN) ---
WG_INTERFACE="wg2"
# Öffentlicher Schlüssel des Servers (MUSS ANGEPASST WERDEN)
SERVER_PUBLIC_KEY=""
# Endpoint (Öffentliche IP oder Domain des Servers, gefolgt vom Port)
SERVER_ENDPOINT=":51822"
# Server-IP im Tunnel (wird als DNS und Peer-IP genutzt)
SERVER_TUNNEL_IP="10.2.0.1"

# --- CLIENT-PARAMETER-EINGABE ---
read -p "Geben Sie den Namen des neuen Clients ein (z.B. 'temp_tablet'): " CLIENT_NAME
read -p "Geben Sie die Dauer der Gültigkeit in Stunden ein (z.B. '12'): " DURATION_H

# --- Überprüfen, ob die IP schon existiert (einfacher Check)
if wg show "$WG_INTERFACE" allowed-ips | grep -q "$CLIENT_IP/32"; then
    echo "❌ FEHLER: Die generierte IP-Adresse $CLIENT_IP/32 ist bereits in Gebrauch. Bitte warten Sie eine Minute oder passen Sie die IP manuell an."
    exit 1
fi

echo "ℹ️ Generierte temporäre Client-IP: $CLIENT_IP/32"

# --- KEYPAIR GENERIEREN ---
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# --- PEER DYNAMISCH HINZUFÜGEN (wg set) ---

echo ""
echo "▶️ Schritt 1: Füge Peer '$CLIENT_NAME' dynamisch zum Interface $WG_INTERFACE hinzu..."
# Server-Konfiguration: Hinzufügen des Clients und seiner /32 IP.
wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_IP/32"
ip -4 route add "$CLIENT_IP/32" dev "$WG_INTERFACE"
echo "✅ Peer '$CLIENT_NAME' mit IP $CLIENT_IP/32 ist jetzt aktiv."

# --- CLIENT-CONFIG GENERIEREN ---
# Dateiname wird sofort festgelegt, um ihn für die Löschung zu verwenden
CONFIG_FILE="$CLIENT_NAME-$HOUR-$MINUTE-temp.conf"

CLIENT_CONFIG=$(cat <<EOF
[Interface]
# Client Name: $CLIENT_NAME (Loescht sich automatisch nach $DURATION_H Stunden)
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = $SERVER_TUNNEL_IP

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = $SERVER_TUNNEL_IP/32, 10.2.0.0/16
PersistentKeepalive = 25
EOF
)

# Speichere die Datei
echo "$CLIENT_CONFIG" > "$CONFIG_FILE"

# --- AUTOMATISCHE LÖSCHUNG MIT 'at' PLANEN ---
EXPIRY_TIME=$(date -d "+$DURATION_H hours" +"%H:%M %Y-%m-%d")

# Das Kommando zum Löschen des Peers UND der Konfigurationsdatei
DELETE_COMMANDS=$(cat <<EOC
wg set $WG_INTERFACE peer $CLIENT_PUBLIC_KEY remove
rm "$CONFIG_FILE"
ip -4 route delete $CLIENT_IP/32 dev $WG_INTERFACE
echo "WireGuard Job abgeschlossen: Peer $CLIENT_NAME und Konfigurationsdatei $CONFIG_FILE gelöscht."
EOC
)

# Den Job bei 'at' eintragen
echo "$DELETE_COMMANDS" | at "$EXPIRY_TIME" 2>/dev/null

echo "▶️ Schritt 2: Automatisches Entfernen von Peer und Datei in $DURATION_H Stunden geplant."
echo "   Der Job wird automatisch am $EXPIRY_TIME ausgeführt."

# --- ERGEBNISSE AUSGEBEN ---

echo ""
echo "========================================================================"
echo "✅ KONFIGURATION FÜR CLIENT '$CLIENT_NAME' ERFOLGREICH GENERIERT"
echo "========================================================================"
echo "--- Client-IP: $CLIENT_IP/32 ---"

# Ausgabe der Client-Config
echo "$CLIENT_CONFIG"

echo ""
echo "Speicherort der Client-Konfig: $CONFIG_FILE (WIRD AUTOMATISCH GELÖSCHT)"

echo ""
echo "▶️ QR-Code für mobile Geräte (Android/iOS) wird generiert..."
qrencode -t ansiutf8 < "$CONFIG_FILE"

echo "========================================================================"
echo "💡 HINWEIS: Der Client und die Datei werden am $EXPIRY_TIME automatisch entfernt."
echo "   Überprüfen Sie geplante Jobs mit: 'atq'"
echo "========================================================================"
