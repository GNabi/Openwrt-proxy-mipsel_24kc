#!/bin/sh
# universal_config.sh adapted for mipsel_24kc architecture (e.g. MIPS24Kc routers).
# Removed device architecture/model check. Updated Opera Proxy IPK URL for mipsel_24kc.
# All other logic (AmneziaWG installation, WARP configuration, firewall setup, fallbacks) is preserved.

# Ensure package lists are up to date
opkg update

# Install AmneziaWG packages (tools, LuCI GUI, and kernel module)
echo "Installing AmneziaWG packages (tools, LuCI, kmod)..."
opkg install amneziawg-tools luci-app-amneziawg kmod-amneziawg
if [ "$?" -ne 0 ]; then
    echo "Error: Failed to install one or more AmneziaWG packages. Please check your package sources."
    # We proceed even if this fails, as packages might already be installed.
fi

# Attempt to obtain a Cloudflare WARP configuration for AmneziaWG from available online generators
echo "Obtaining Cloudflare WARP configuration..."
WARP_CONFIG=""
# Try multiple config generator services
for GEN_URL in "https://warp.llimonix.pw/" "https://topor-warp.vercel.app/" "https://warp-gen.vercel.app/"; do
    echo "Trying $GEN_URL"
    if command -v curl >/dev/null 2>&1; then
        WARP_CONFIG="$(curl -fsSL --max-time 15 "$GEN_URL" || true)"
    else
        WARP_CONFIG="$(wget -qO- "$GEN_URL" || true)"
    fi
    # Check if the fetched content appears to be a valid config (contains a WireGuard PrivateKey)
    if echo "$WARP_CONFIG" | grep -q "PrivateKey"; then
        echo "WARP configuration retrieved successfully from $GEN_URL"
        break
    fi
done

if ! echo "$WARP_CONFIG" | grep -q "PrivateKey"; then
    WARP_CONFIG=""
fi

if [ -n "$WARP_CONFIG" ]; then
    echo "Configuring AmneziaWG interface with WARP settings..."

    # Parse key and address from the WARP config
    PRIVATE_KEY="$(echo "$WARP_CONFIG" | grep -m1 'PrivateKey' | cut -d'=' -f2 | xargs)"
    ADDRESS_LINE="$(echo "$WARP_CONFIG" | grep -m1 'Address' | cut -d'=' -f2 | xargs)"
    # Split addresses (IPv4, IPv6) if both present
    ADDR1="$(echo "$ADDRESS_LINE" | cut -d',' -f1 | xargs)"
    ADDR2="$(echo "$ADDRESS_LINE" | cut -d',' -f2 | xargs)"
    # Parse peer public key and endpoint
    PUBLIC_KEY="$(echo "$WARP_CONFIG" | grep -m1 'PublicKey' | cut -d'=' -f2 | xargs)"
    ENDPOINT="$(echo "$WARP_CONFIG" | grep -m1 'Endpoint' | cut -d'=' -f2 | xargs)"
    ENDPOINT_HOST="$(echo "$ENDPOINT" | cut -d':' -f1)"
    ENDPOINT_PORT="$(echo "$ENDPOINT" | cut -d':' -f2)"
    [ -z "$ENDPOINT_PORT" ] && ENDPOINT_PORT="51820"  # default to 51820 if not specified

    # Parse AmneziaWG-specific parameters (Jitter and obfuscation settings)
    AWG_JC="$(echo "$WARP_CONFIG" | grep -m1 '^Jc' | cut -d'=' -f2 | xargs)"
    AWG_JMIN="$(echo "$WARP_CONFIG" | grep -m1 '^Jmin' | cut -d'=' -f2 | xargs)"
    AWG_JMAX="$(echo "$WARP_CONFIG" | grep -m1 '^Jmax' | cut -d'=' -f2 | xargs)"
    AWG_S1="$(echo "$WARP_CONFIG" | grep -m1 '^S1' | cut -d'=' -f2 | xargs)"
    AWG_S2="$(echo "$WARP_CONFIG" | grep -m1 '^S2' | cut -d'=' -f2 | xargs)"
    AWG_H1="$(echo "$WARP_CONFIG" | grep -m1 '^H1' | cut -d'=' -f2 | xargs)"
    AWG_H2="$(echo "$WARP_CONFIG" | grep -m1 '^H2' | cut -d'=' -f2 | xargs)"
    AWG_H3="$(echo "$WARP_CONFIG" | grep -m1 '^H3' | cut -d'=' -f2 | xargs)"
    AWG_H4="$(echo "$WARP_CONFIG" | grep -m1 '^H4' | cut -d'=' -f2 | xargs)"

    # Configure network interface for AmneziaWG (awg0)
    uci delete network.awg0 2>/dev/null
    uci set network.awg0="interface"
    uci set network.awg0.proto="amneziawg"
    uci set network.awg0.private_key="$PRIVATE_KEY"
    uci set network.awg0.listen_port="51821"  # use a non-standard listen port for AWG
    # Set assigned IP addresses
    if [ -n "$ADDR1" ]; then
        uci add_list network.awg0.addresses="$ADDR1"
    fi
    if [ -n "$ADDR2" ]; then
        uci add_list network.awg0.addresses="$ADDR2"
    fi
    # Apply AmneziaWG obfuscation parameters
    [ -n "$AWG_JC" ] && uci set network.awg0.awg_jc="$AWG_JC"
    [ -n "$AWG_JMIN" ] && uci set network.awg0.awg_jmin="$AWG_JMIN"
    [ -n "$AWG_JMAX" ] && uci set network.awg0.awg_jmax="$AWG_JMAX"
    [ -n "$AWG_S1" ] && uci set network.awg0.awg_s1="$AWG_S1"
    [ -n "$AWG_S2" ] && uci set network.awg0.awg_s2="$AWG_S2"
    [ -n "$AWG_H1" ] && uci set network.awg0.awg_h1="$AWG_H1"
    [ -n "$AWG_H2" ] && uci set network.awg0.awg_h2="$AWG_H2"
    [ -n "$AWG_H3" ] && uci set network.awg0.awg_h3="$AWG_H3"
    [ -n "$AWG_H4" ] && uci set network.awg0.awg_h4="$AWG_H4"

    # Configure peer (Cloudflare WARP) for awg0
    # Use a section type named "amneziawg_awg0" to attach it to awg0 interface
    uci add network amneziawg_awg0
    uci set network.@amneziawg_awg0[-1].public_key="$PUBLIC_KEY"
    uci set network.@amneziawg_awg0[-1].endpoint_host="$ENDPOINT_HOST"
    uci set network.@amneziawg_awg0[-1].endpoint_port="$ENDPOINT_PORT"
    uci set network.@amneziawg_awg0[-1].allowed_ips="0.0.0.0/0"
    uci add_list network.@amneziawg_awg0[-1].allowed_ips="::/0"
    uci set network.@amneziawg_awg0[-1].persistent_keepalive="25"
    uci set network.@amneziawg_awg0[-1].name="WARP_AWG_peer"

    # Commit network changes
    uci commit network

    # Set up firewall zone for AmneziaWG
    echo "Configuring firewall for AmneziaWG..."
    # Create a new zone named 'awg0' (VPN zone)
    uci add firewall zone
    uci set firewall.@zone[-1].name="awg0"
    uci set firewall.@zone[-1].network="awg0"
    uci set firewall.@zone[-1].input="REJECT"
    uci set firewall.@zone[-1].output="ACCEPT"
    uci set firewall.@zone[-1].forward="REJECT"
    uci set firewall.@zone[-1].masq="1"
    uci set firewall.@zone[-1].mtu_fix="1"
    # Allow LAN -> AWG forwarding
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src="lan"
    uci set firewall.@forwarding[-1].dest="awg0"
    uci set firewall.@forwarding[-1].name="lan-to-awg0"

    uci commit firewall

    # Bring up the AmneziaWG (awg0) interface
    ifup awg0

    echo "AmneziaWG interface 'awg0' has been set up and started using Cloudflare WARP."
    echo "All network traffic should now be routed through the WARP tunnel."
else
    echo "Failed to retrieve WARP configuration. Enabling fallback method (YouTube Unblock & Opera Proxy)..."

    # Fallback: YouTube Unblock (if any specific rules or settings are needed for YouTube, they would be applied here)
    # [No explicit actions provided for YouTubeUnblock in this script; assuming handled by Opera Proxy usage]

    # Install Opera Proxy (HTTP proxy through Opera VPN) for fallback
    echo "Installing Opera Proxy package for fallback..."
    OPERA_IPK_URL="https://github.com/GNabi/Openwrt-proxy-mipsel_24kc/raw/refs/heads/main/opera-proxy_1.9.0-r1_mipsel_24kc.ipk"
    OPERA_IPK_FILE="/tmp/opera-proxy.ipk"
    if ! wget -qO "$OPERA_IPK_FILE" "$OPERA_IPK_URL"; then
        echo "Error: Could not download Opera Proxy package."
    else
        opkg install "$OPERA_IPK_FILE" && rm -f "$OPERA_IPK_FILE"
    fi

    # Start Opera Proxy service
    if /etc/init.d/opera-proxy start; then
        /etc/init.d/opera-proxy enable
        echo "Opera Proxy service started (listening on 127.0.0.1:18080)."
        echo "Configure your devices or browser to use this HTTP proxy (router IP port 18080) to access blocked sites."
    else
        echo "Error: Opera Proxy failed to start. Ensure the package was installed correctly."
    fi

    echo "Fallback mode activated. Traffic will NOT be tunneled via WARP, please use the Opera Proxy for accessing blocked content."
fi
