#!/bin/bash

# --- SECURITY CHECK AND VARIABLE SETUP ---
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi

# Check required tools (wg, qrencode, at)
if ! command -v wg &> /dev/null; then
    echo "Required tool 'wg' not found. Please install it."
    exit 1
fi

if ! command -v qrencode &> /dev/null; then
    echo "Required tool 'qrencode' not found. Please install it."
    exit 1
fi

if ! command -v at &> /dev/null; then
    echo "Required tool 'at' not found. Please install it."
    exit 1
fi

# --- IP GENERATION BASED ON CURRENT TIMESTAMP ---
HOUR=$(printf "%d" $(date +%H))
MINUTE=$(printf "%d" $(date +%M))

# Generate client IP in the 10.2.0.0/16 network based on hour:minute
CLIENT_IP="10.2.$HOUR.$MINUTE"

# --- SERVER PARAMETERS (ADJUST AS REQUIRED) ---
WG_INTERFACE="wg2"

# Server public key (MUST BE SET)
SERVER_PUBLIC_KEY=""

# Public endpoint of the WireGuard server (IP/DNS:PORT)
SERVER_ENDPOINT=":51822"

# Server tunnel IP (used as DNS and peer address)
SERVER_TUNNEL_IP="10.2.0.1"

# --- CLIENT INPUT ---
read -p "Enter the name of the new client (e.g. 'temp_tablet'): " CLIENT_NAME
read -p "Enter validity duration in hours (e.g. '12'): " DURATION_H

# --- CHECK IF IP IS ALREADY IN USE ---
if wg show "$WG_INTERFACE" allowed-ips | grep -q "$CLIENT_IP/32"; then
    echo "ERROR: Generated IP address $CLIENT_IP/32 is already in use. Please wait a minute or adjust manually."
    exit 1
fi

echo "Generated temporary client IP: $CLIENT_IP/32"

# --- KEYPAIR GENERATION ---
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# --- ADD PEER DYNAMICALLY ---
echo ""
echo "Adding peer '$CLIENT_NAME' dynamically to interface $WG_INTERFACE..."
wg set "$WG_INTERFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_IP/32"
ip -4 route add "$CLIENT_IP/32" dev "$WG_INTERFACE"
echo "Peer '$CLIENT_NAME' with IP $CLIENT_IP/32 is now active."

# --- CLIENT CONFIG GENERATION ---
CONFIG_FILE="$CLIENT_NAME-$HOUR-$MINUTE-temp.conf"

CLIENT_CONFIG=$(cat <<EOF
[Interface]
# Client Name: $CLIENT_NAME (auto-removed after $DURATION_H hours)
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

# Save config file
echo "$CLIENT_CONFIG" > "$CONFIG_FILE"

# --- SCHEDULE AUTOMATIC REMOVAL USING 'at' ---
EXPIRY_TIME=$(date -d "+$DURATION_H hours" +"%H:%M %Y-%m-%d")

DELETE_COMMANDS=$(cat <<EOC
wg set $WG_INTERFACE peer $CLIENT_PUBLIC_KEY remove
rm "$CONFIG_FILE"
ip -4 route delete $CLIENT_IP/32 dev $WG_INTERFACE
echo "WireGuard cleanup completed: Peer $CLIENT_NAME and config $CONFIG_FILE removed."
EOC
)

echo "$DELETE_COMMANDS" | at "$EXPIRY_TIME" 2>/dev/null

echo "Automatic removal scheduled in $DURATION_H hours ($EXPIRY_TIME)."

# --- OUTPUT ---
echo ""
echo "============================================================"
echo "CLIENT CONFIGURATION FOR '$CLIENT_NAME' GENERATED"
echo "============================================================"
echo "Client IP: $CLIENT_IP/32"

echo "$CLIENT_CONFIG"

echo ""
echo "Config file location: $CONFIG_FILE (AUTO-DELETED)"

echo ""
echo "Generating QR code for mobile devices..."
qrencode -t ansiutf8 < "$CONFIG_FILE"

echo "============================================================"
echo "NOTE: Client and config will be removed automatically at $EXPIRY_TIME"
echo "Check scheduled jobs with: atq"
echo "============================================================"
