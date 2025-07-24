#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Config
MAX_PARALLEL_SCANS=10
MAX_SCAN_TIME=300
RESULTS_DIR="./results"
mkdir -p "$RESULTS_DIR"

# Trap Ctrl+C
trap 'echo -e "\n${YELLOW}Scan cancelled.${NC}"; exit 1' SIGINT

# Check required tools
check_tools() {
    command -v nmap >/dev/null || { echo -e "${RED}nmap not found${NC}"; exit 1; }
    command -v arp-scan >/dev/null || echo -e "${YELLOW}arp-scan not found (optional)${NC}"
}

# Get available networks
get_networks() {
    ip route | grep -E '192\.168\.|10\.|172\.' | awk '{print $1}' | sort -u
}

# Choose network interactively
select_network() {
    echo -e "${BLUE}Available Networks:${NC}"
    networks=($(get_networks))
    for i in "${!networks[@]}"; do
        echo "$((i+1))) ${networks[i]}"
    done
    echo "$(( ${#networks[@]} + 1 ))) Enter manually"
    read -p "Choose an option: " choice
    if [ "$choice" -eq "$(( ${#networks[@]} + 1 ))" ]; then
        read -p "Enter network (e.g., 192.168.1.0/24): " NET
    else
        NET="${networks[$((choice-1))]}"
    fi
}

# Discover live hosts using nmap and arp-scan
discover_hosts() {
    echo -e "${BLUE}Scanning live hosts on $NET...${NC}"
    LIVE_HOSTS_FILE="$RESULTS_DIR/live_hosts_$(date +%s).txt"
    timeout $MAX_SCAN_TIME nmap -sn "$NET" | grep "Nmap scan report" | awk '{print $NF}' > "$LIVE_HOSTS_FILE"

    if command -v arp-scan >/dev/null; then
        sudo arp-scan -l | grep -E '192\.168\.|10\.|172\.' | awk '{print $1}' >> "$LIVE_HOSTS_FILE"
    fi

    sort -u "$LIVE_HOSTS_FILE" > "${LIVE_HOSTS_FILE}.tmp"
    mv "${LIVE_HOSTS_FILE}.tmp" "$LIVE_HOSTS_FILE"
    echo -e "${GREEN}Live hosts found: $(wc -l < "$LIVE_HOSTS_FILE")${NC}"
}

# Scan ports on live hosts
scan_ports() {
    echo -e "${BLUE}Starting port scan...${NC}"
    SCAN_RESULTS_FILE="$RESULTS_DIR/scan_results_$(date +%s).txt"

    scan_host() {
        host="$1"
        timeout 30 nmap -F "$host" >> "$SCAN_RESULTS_FILE" 2>/dev/null
    }

    job_count=0
    while read -r host; do
        scan_host "$host" &
        ((job_count++))
        if [ "$job_count" -ge "$MAX_PARALLEL_SCANS" ]; then
            wait
            job_count=0
        fi
    done < "$LIVE_HOSTS_FILE"
    wait
    echo -e "${GREEN}Port scanning completed. Results saved to:${NC} $SCAN_RESULTS_FILE"
}

# --- Main ---
check_tools
select_network
discover_hosts
scan_ports
