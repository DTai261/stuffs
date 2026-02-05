#!/bin/bash

# VPS Setup Script
# Interactive menu-driven script for VPS setup tasks

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
OS_TYPE=""
PKG_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""
UPGRADE_CMD=""

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                OS_TYPE="debian"
                PKG_MANAGER="apt"
                INSTALL_CMD="apt-get install -y"
                UPDATE_CMD="apt-get update"
                UPGRADE_CMD="apt-get upgrade -y"
                ;;
            centos|rhel|fedora|rocky|almalinux)
                OS_TYPE="rhel"
                if command -v dnf &> /dev/null; then
                    PKG_MANAGER="dnf"
                    INSTALL_CMD="dnf install -y"
                    UPDATE_CMD="dnf check-update"
                    UPGRADE_CMD="dnf upgrade -y"
                else
                    PKG_MANAGER="yum"
                    INSTALL_CMD="yum install -y"
                    UPDATE_CMD="yum check-update"
                    UPGRADE_CMD="yum upgrade -y"
                fi
                ;;
            arch|manjaro)
                OS_TYPE="arch"
                PKG_MANAGER="pacman"
                INSTALL_CMD="pacman -S --noconfirm"
                UPDATE_CMD="pacman -Sy"
                UPGRADE_CMD="pacman -Su --noconfirm"
                ;;
            *)
                echo -e "${RED}Unsupported OS: $ID${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${RED}Cannot detect OS. /etc/os-release not found.${NC}"
        exit 1
    fi
}

# Backup file with date suffix
backup_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}File $file does not exist. Skipping backup.${NC}"
        return 0
    fi
    
    local date_suffix=$(date +%d%m%y)
    local backup_file="${file}_${date_suffix}.old"
    
    if cp "$file" "$backup_file"; then
        echo -e "${GREEN}Backup created: $backup_file${NC}"
        return 0
    else
        echo -e "${RED}Failed to create backup for $file${NC}"
        return 1
    fi
}

# Check if package is installed
is_package_installed() {
    local package="$1"
    
    case $PKG_MANAGER in
        apt)
            # Use dpkg-query which is more reliable than grep on dpkg -l
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
                return 0
            fi
            # Fallback: check if binary exists (for packages like python3 -> python3 command)
            local bin_name=$(basename "$package" 2>/dev/null)
            if command -v "$bin_name" &> /dev/null; then
                return 0
            fi
            return 1
            ;;
        yum|dnf)
            if rpm -q "$package" &> /dev/null; then
                return 0
            fi
            # Fallback: check if binary exists
            local bin_name=$(basename "$package" 2>/dev/null)
            if command -v "$bin_name" &> /dev/null; then
                return 0
            fi
            return 1
            ;;
        pacman)
            if pacman -Qi "$package" &> /dev/null; then
                return 0
            fi
            # Fallback: check if binary exists
            local bin_name=$(basename "$package" 2>/dev/null)
            if command -v "$bin_name" &> /dev/null; then
                return 0
            fi
            return 1
            ;;
    esac
}

# Check if any package in a space-separated list is installed
is_any_package_installed() {
    local package_list="$1"
    for pkg in $package_list; do
        if is_package_installed "$pkg"; then
            return 0
        fi
    done
    return 1
}

# Install package
install_package() {
    local package="$1"
    
    if is_package_installed "$package"; then
        echo -e "${YELLOW}$package is already installed.${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Installing $package...${NC}"
    if $INSTALL_CMD "$package"; then
        echo -e "${GREEN}$package installed successfully.${NC}"
        return 0
    else
        echo -e "${RED}Failed to install $package${NC}"
        return 1
    fi
}

# Update and upgrade system
update_system() {
    echo -e "${BLUE}Updating package lists...${NC}"
    $UPDATE_CMD || echo -e "${YELLOW}Update check completed with warnings.${NC}"
    
    echo -e "${BLUE}Upgrading system packages...${NC}"
    $UPGRADE_CMD || echo -e "${YELLOW}Upgrade completed with warnings.${NC}"
    
    echo -e "${GREEN}System update completed.${NC}"
}

# Configure SSH
configure_ssh() {
    local sshd_config="/etc/ssh/sshd_config"
    
    if [ ! -f "$sshd_config" ]; then
        echo -e "${RED}SSH config file not found: $sshd_config${NC}"
        return 1
    fi
    
    backup_file "$sshd_config"
    
    echo -e "${BLUE}SSH Configuration${NC}"
    echo "1) Allow/Disallow password authentication"
    echo "2) Allow/Disallow root SSH login"
    echo "3) Configure SSH key authentication"
    read -p "Choose option [1-3]: " ssh_option
    
    case $ssh_option in
        1)
            echo "1) Allow password authentication"
            echo "2) Disallow password authentication"
            read -p "Choose option [1-2]: " pass_option
            
            if [ "$pass_option" = "1" ]; then
                sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
                echo -e "${GREEN}Password authentication enabled.${NC}"
            else
                sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
                echo -e "${GREEN}Password authentication disabled.${NC}"
            fi
            ;;
        2)
            echo "1) Allow root SSH login"
            echo "2) Disallow root SSH login"
            read -p "Choose option [1-2]: " root_option
            
            if [ "$root_option" = "1" ]; then
                sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$sshd_config"
                sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$sshd_config"
                echo -e "${GREEN}Root SSH login enabled.${NC}"
            else
                sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
                echo -e "${GREEN}Root SSH login disabled.${NC}"
            fi
            ;;
        3)
            sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
            sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
            sed -i 's/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/' "$sshd_config"
            echo -e "${GREEN}SSH key authentication configured.${NC}"
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            return 1
            ;;
    esac
    
    echo -e "${BLUE}Reloading SSH service...${NC}"
    if systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || service sshd reload 2>/dev/null || service ssh reload 2>/dev/null; then
        echo -e "${GREEN}SSH service reloaded.${NC}"
    else
        echo -e "${YELLOW}Please manually reload SSH service.${NC}"
    fi
}

# Change hostname
change_hostname() {
    read -p "Enter new hostname: " new_hostname
    
    if [ -z "$new_hostname" ]; then
        echo -e "${RED}Hostname cannot be empty.${NC}"
        return 1
    fi
    
    # Backup /etc/hostname if it exists
    if [ -f /etc/hostname ]; then
        backup_file "/etc/hostname"
        echo "$new_hostname" > /etc/hostname
    fi
    
    # Update /etc/hosts
    if [ -f /etc/hosts ]; then
        backup_file "/etc/hosts"
        sed -i "s/^127.0.0.1.*localhost.*/127.0.0.1 localhost $new_hostname/" /etc/hosts
        sed -i "s/^::1.*localhost.*/::1 localhost $new_hostname/" /etc/hosts
    fi
    
    hostnamectl set-hostname "$new_hostname" 2>/dev/null || true
    
    echo -e "${GREEN}Hostname changed to: $new_hostname${NC}"
    echo -e "${YELLOW}Please reboot for changes to take full effect.${NC}"
}

# Install packages menu
install_packages_menu() {
    # Package list with OS-specific names
    declare -A packages
    
    case $OS_TYPE in
        debian)
            packages=(
                ["htop"]="htop"
                ["tmux"]="tmux"
                ["git"]="git"
                ["curl"]="curl"
                ["wget"]="wget"
                ["vim"]="vim"
                ["nano"]="nano"
                ["net-tools"]="net-tools"
                ["ufw"]="ufw"
                ["fail2ban"]="fail2ban"
                ["build-essential"]="build-essential"
                ["python3"]="python3"
                ["python3-pip"]="python3-pip"
                ["go"]="golang-go"
                ["nodejs"]="nodejs"
                ["npm"]="npm"
                ["docker"]="docker.io"
                ["docker-compose"]="docker-compose"
                ["nginx"]="nginx"
                ["apache2"]="apache2"
                ["postgresql"]="postgresql"
                ["mysql-server"]="mysql-server"
                ["certbot"]="certbot"
                ["openssh-server"]="openssh-server"
                ["unzip"]="unzip"
                ["zip"]="zip"
                ["tree"]="tree"
                ["jq"]="jq"
                ["rsync"]="rsync"
            )
            ;;
        rhel)
            packages=(
                ["htop"]="htop"
                ["tmux"]="tmux"
                ["git"]="git"
                ["curl"]="curl"
                ["wget"]="wget"
                ["vim"]="vim"
                ["nano"]="nano"
                ["net-tools"]="net-tools"
                ["ufw"]="firewalld"
                ["fail2ban"]="fail2ban"
                ["build-essential"]="gcc gcc-c++ make"
                ["python3"]="python3"
                ["python3-pip"]="python3-pip"
                ["go"]="golang"
                ["nodejs"]="nodejs"
                ["npm"]="npm"
                ["docker"]="docker"
                ["docker-compose"]="docker-compose"
                ["nginx"]="nginx"
                ["apache2"]="httpd"
                ["postgresql"]="postgresql-server"
                ["mysql-server"]="mysql-server"
                ["certbot"]="certbot"
                ["openssh-server"]="openssh-server"
                ["unzip"]="unzip"
                ["zip"]="zip"
                ["tree"]="tree"
                ["jq"]="jq"
                ["rsync"]="rsync"
            )
            ;;
        arch)
            packages=(
                ["htop"]="htop"
                ["tmux"]="tmux"
                ["git"]="git"
                ["curl"]="curl"
                ["wget"]="wget"
                ["vim"]="vim"
                ["nano"]="nano"
                ["net-tools"]="net-tools"
                ["ufw"]="ufw"
                ["fail2ban"]="fail2ban"
                ["build-essential"]="base-devel"
                ["python3"]="python"
                ["python3-pip"]="python-pip"
                ["go"]="go"
                ["nodejs"]="nodejs"
                ["npm"]="npm"
                ["docker"]="docker"
                ["docker-compose"]="docker-compose"
                ["nginx"]="nginx"
                ["apache2"]="apache"
                ["postgresql"]="postgresql"
                ["mysql-server"]="mysql"
                ["certbot"]="certbot"
                ["openssh-server"]="openssh"
                ["unzip"]="unzip"
                ["zip"]="zip"
                ["tree"]="tree"
                ["jq"]="jq"
                ["rsync"]="rsync"
            )
            ;;
    esac
    
    echo -e "${BLUE}Available packages:${NC}"
    local i=1
    local package_keys=()
    for key in "${!packages[@]}"; do
        printf "%2d) %-20s" "$i" "$key"
        local pkg_value="${packages[$key]}"
        local is_installed=0
        
        # Check if any package in the list is installed (handles multi-package entries)
        if is_any_package_installed "$pkg_value"; then
            is_installed=1
        else
            # Also check common binary names that might differ from package names
            case $key in
                curl)
                    if command -v curl &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                wget)
                    if command -v wget &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                nano)
                    if command -v nano &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                vim)
                    if command -v vim &> /dev/null || command -v vi &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                git)
                    if command -v git &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                python3)
                    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                python3-pip)
                    if command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                go)
                    if command -v go &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                nodejs)
                    if command -v node &> /dev/null || command -v nodejs &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                npm)
                    if command -v npm &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                docker)
                    if command -v docker &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                docker-compose)
                    if command -v docker-compose &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                nginx)
                    if command -v nginx &> /dev/null || systemctl is-active --quiet nginx 2>/dev/null; then
                        is_installed=1
                    fi
                    ;;
                apache2)
                    if command -v apache2 &> /dev/null || command -v httpd &> /dev/null || systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
                        is_installed=1
                    fi
                    ;;
                postgresql)
                    if command -v psql &> /dev/null || systemctl is-active --quiet postgresql 2>/dev/null; then
                        is_installed=1
                    fi
                    ;;
                mysql-server)
                    if command -v mysql &> /dev/null || systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null; then
                        is_installed=1
                    fi
                    ;;
                net-tools)
                    if command -v ifconfig &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                build-essential)
                    if command -v gcc &> /dev/null || command -v make &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                htop)
                    if command -v htop &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                tmux)
                    if command -v tmux &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                unzip)
                    if command -v unzip &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                zip)
                    if command -v zip &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                tree)
                    if command -v tree &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                jq)
                    if command -v jq &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                rsync)
                    if command -v rsync &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                ufw)
                    if command -v ufw &> /dev/null || systemctl is-active --quiet ufw 2>/dev/null || systemctl is-active --quiet firewalld 2>/dev/null; then
                        is_installed=1
                    fi
                    ;;
                fail2ban)
                    if command -v fail2ban-client &> /dev/null || systemctl is-active --quiet fail2ban 2>/dev/null; then
                        is_installed=1
                    fi
                    ;;
                certbot)
                    if command -v certbot &> /dev/null; then
                        is_installed=1
                    fi
                    ;;
                openssh-server)
                    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null || [ -f /etc/ssh/sshd_config ]; then
                        is_installed=1
                    fi
                    ;;
            esac
        fi
        
        if [ $is_installed -eq 1 ]; then
            echo -e " ${GREEN}[INSTALLED]${NC}"
        else
            echo -e " ${YELLOW}[NOT INSTALLED]${NC}"
        fi
        package_keys+=("$key")
        ((i++))
    done
    echo "$i) Install all packages"
    echo "$((i+1))) Back to main menu"
    
    read -p "Choose option [1-$((i+1))]: " pkg_option
    
    if [ "$pkg_option" = "$i" ]; then
        # Install all
        echo -e "${BLUE}Installing all packages...${NC}"
        for key in "${!packages[@]}"; do
            local pkg_name="${packages[$key]}"
            for pkg in $pkg_name; do
                install_package "$pkg"
            done
        done
    elif [ "$pkg_option" = "$((i+1))" ]; then
        return 0
    elif [ "$pkg_option" -ge 1 ] && [ "$pkg_option" -le $((i-1)) ]; then
        local selected_key="${package_keys[$((pkg_option-1))]}"
        local pkg_name="${packages[$selected_key]}"
        for pkg in $pkg_name; do
            install_package "$pkg"
        done
    else
        echo -e "${RED}Invalid option.${NC}"
    fi
}

# Sync system time
sync_system_time() {
    echo -e "${BLUE}Syncing system time with UTC...${NC}"
    
    local time_synced=0
    
    # Method 1: Try NTP synchronization (chrony preferred, then ntp)
    if command -v chronyd &> /dev/null || command -v chrony &> /dev/null || command -v chronyc &> /dev/null; then
        echo -e "${BLUE}Using chrony for time synchronization...${NC}"
        local chrony_service=""
        if systemctl list-units --type=service 2>/dev/null | grep -q "chronyd.service"; then
            chrony_service="chronyd"
        elif systemctl list-units --type=service 2>/dev/null | grep -q "chrony.service"; then
            chrony_service="chrony"
        fi
        
        if [ -z "$chrony_service" ] || ! systemctl is-active --quiet "$chrony_service" 2>/dev/null; then
            echo -e "${YELLOW}chrony service not running. Installing and starting chrony...${NC}"
            case $PKG_MANAGER in
                apt)
                    install_package "chrony"
                    chrony_service="chrony"
                    systemctl enable chrony 2>/dev/null || systemctl enable chronyd 2>/dev/null
                    systemctl start chrony 2>/dev/null || systemctl start chronyd 2>/dev/null
                    if systemctl is-active --quiet chronyd 2>/dev/null; then
                        chrony_service="chronyd"
                    fi
                    ;;
                yum|dnf)
                    install_package "chrony"
                    chrony_service="chronyd"
                    systemctl enable chronyd
                    systemctl start chronyd
                    ;;
                pacman)
                    install_package "chrony"
                    chrony_service="chronyd"
                    systemctl enable chronyd
                    systemctl start chronyd
                    ;;
            esac
        fi
        
        # Wait for chrony to sync
        sleep 3
        if command -v chronyc &> /dev/null; then
            if chronyc sources 2>/dev/null | grep -q "^\^\*"; then
                echo -e "${GREEN}Time synchronized using chrony.${NC}"
                time_synced=1
            else
                # Force chrony to make step adjustment
                chronyc makestep 2>/dev/null
                sleep 2
                if chronyc sources 2>/dev/null | grep -q "^\^\*"; then
                    echo -e "${GREEN}Time synchronized using chrony.${NC}"
                    time_synced=1
                fi
            fi
        elif [ -n "$chrony_service" ] && systemctl is-active --quiet "$chrony_service" 2>/dev/null; then
            echo -e "${GREEN}chrony service is running. Time should be synchronized.${NC}"
            time_synced=1
        fi
    elif command -v ntpd &> /dev/null || command -v ntpdate &> /dev/null; then
        echo -e "${BLUE}Using NTP for time synchronization...${NC}"
        if command -v ntpdate &> /dev/null; then
            if ntpdate -q pool.ntp.org 2>/dev/null || ntpdate -q time.google.com 2>/dev/null || ntpdate -q time.cloudflare.com 2>/dev/null; then
                echo -e "${GREEN}Time synchronized using ntpdate.${NC}"
                time_synced=1
            fi
        elif command -v ntpd &> /dev/null; then
            if ! systemctl is-active --quiet ntpd 2>/dev/null; then
                systemctl start ntpd 2>/dev/null
                sleep 3
            fi
            if ntpq -p 2>/dev/null | grep -q "^\*"; then
                echo -e "${GREEN}Time synchronized using ntpd.${NC}"
                time_synced=1
            fi
        fi
    else
        # Try to install chrony or ntp
        echo -e "${YELLOW}NTP tools not found. Attempting to install...${NC}"
        case $PKG_MANAGER in
            apt)
                if install_package "chrony"; then
                    local chrony_service="chrony"
                    systemctl enable chrony 2>/dev/null || systemctl enable chronyd 2>/dev/null
                    systemctl start chrony 2>/dev/null || systemctl start chronyd 2>/dev/null
                    if systemctl is-active --quiet chronyd 2>/dev/null; then
                        chrony_service="chronyd"
                    fi
                    sleep 3
                    if command -v chronyc &> /dev/null; then
                        chronyc makestep 2>/dev/null
                        if chronyc sources 2>/dev/null | grep -q "^\^\*"; then
                            echo -e "${GREEN}Time synchronized using chrony.${NC}"
                            time_synced=1
                        fi
                    elif systemctl is-active --quiet "$chrony_service" 2>/dev/null; then
                        echo -e "${GREEN}chrony service is running. Time should be synchronized.${NC}"
                        time_synced=1
                    fi
                fi
                ;;
            yum|dnf)
                if install_package "chrony"; then
                    systemctl enable chronyd
                    systemctl start chronyd
                    sleep 3
                    if command -v chronyc &> /dev/null; then
                        chronyc makestep 2>/dev/null
                        if chronyc sources 2>/dev/null | grep -q "^\^\*"; then
                            echo -e "${GREEN}Time synchronized using chrony.${NC}"
                            time_synced=1
                        fi
                    elif systemctl is-active --quiet chronyd 2>/dev/null; then
                        echo -e "${GREEN}chrony service is running. Time should be synchronized.${NC}"
                        time_synced=1
                    fi
                fi
                ;;
            pacman)
                if install_package "chrony"; then
                    systemctl enable chronyd
                    systemctl start chronyd
                    sleep 3
                    if command -v chronyc &> /dev/null; then
                        chronyc makestep 2>/dev/null
                        if chronyc sources 2>/dev/null | grep -q "^\^\*"; then
                            echo -e "${GREEN}Time synchronized using chrony.${NC}"
                            time_synced=1
                        fi
                    elif systemctl is-active --quiet chronyd 2>/dev/null; then
                        echo -e "${GREEN}chrony service is running. Time should be synchronized.${NC}"
                        time_synced=1
                    fi
                fi
                ;;
        esac
    fi
    
    # Method 2: Fallback to HTTP time API
    if [ $time_synced -eq 0 ]; then
        echo -e "${YELLOW}NTP synchronization failed or unavailable. Trying HTTP time API...${NC}"
        
        local utc_time=""
        local http_sources=(
            "https://worldtimeapi.org/api/timezone/UTC"
            "https://timeapi.io/api/Time/current/zone?timeZone=UTC"
            "https://time.cloudflare.com/api/time"
        )
        
        for source in "${http_sources[@]}"; do
            echo -e "${BLUE}Trying $source...${NC}"
            if command -v curl &> /dev/null; then
                # Try worldtimeapi.org format
                if [[ "$source" == *"worldtimeapi.org"* ]]; then
                    utc_time=$(curl -s "$source" | grep -oP '"datetime":"\K[^"]+' | head -1)
                    if [ -n "$utc_time" ]; then
                        # Convert ISO 8601 to format suitable for date command
                        utc_time=$(echo "$utc_time" | sed 's/T/ /' | sed 's/\.[0-9]*//')
                        break
                    fi
                # Try timeapi.io format
                elif [[ "$source" == *"timeapi.io"* ]]; then
                    utc_time=$(curl -s "$source" | grep -oP '"dateTime":"\K[^"]+' | head -1)
                    if [ -n "$utc_time" ]; then
                        utc_time=$(echo "$utc_time" | sed 's/T/ /' | sed 's/\.[0-9]*//')
                        break
                    fi
                # Try cloudflare format (returns timestamp in nanoseconds)
                elif [[ "$source" == *"cloudflare.com"* ]]; then
                    local response=$(curl -s "$source")
                    local timestamp=$(echo "$response" | grep -oE '"[0-9]+"' | head -1 | tr -d '"')
                    if [ -n "$timestamp" ] && [ "$timestamp" -gt 1000000000 ]; then
                        # Convert nanoseconds to seconds if needed
                        if [ "$timestamp" -gt 1000000000000000000 ]; then
                            timestamp=$((timestamp / 1000000000))
                        fi
                        # Try GNU date first, then BSD date
                        utc_time=$(date -u -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
                        if [ -n "$utc_time" ] && [ "$utc_time" != "1970-01-01 00:00:00" ]; then
                            break
                        fi
                    fi
                fi
            elif command -v wget &> /dev/null; then
                if [[ "$source" == *"worldtimeapi.org"* ]]; then
                    utc_time=$(wget -qO- "$source" | grep -oP '"datetime":"\K[^"]+' | head -1)
                    if [ -n "$utc_time" ]; then
                        utc_time=$(echo "$utc_time" | sed 's/T/ /' | sed 's/\.[0-9]*//')
                        break
                    fi
                fi
            fi
        done
        
        if [ -n "$utc_time" ]; then
            # Set system time (requires root)
            if date -u -s "$utc_time" 2>/dev/null || date -u "$utc_time" 2>/dev/null; then
                # Sync hardware clock
                hwclock --systohc 2>/dev/null || hwclock -w 2>/dev/null || true
                echo -e "${GREEN}Time synchronized using HTTP time API: $utc_time UTC${NC}"
                time_synced=1
            else
                echo -e "${RED}Failed to set system time.${NC}"
            fi
        else
            echo -e "${RED}Failed to fetch time from HTTP sources.${NC}"
        fi
    fi
    
    # Set timezone to UTC
    if [ $time_synced -eq 1 ]; then
        echo -e "${BLUE}Setting timezone to UTC...${NC}"
        if command -v timedatectl &> /dev/null; then
            timedatectl set-timezone UTC 2>/dev/null && echo -e "${GREEN}Timezone set to UTC.${NC}" || echo -e "${YELLOW}Could not set timezone automatically.${NC}"
        elif [ -f /etc/localtime ]; then
            backup_file "/etc/localtime"
            ln -sf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null && echo -e "${GREEN}Timezone set to UTC.${NC}" || echo -e "${YELLOW}Could not set timezone automatically.${NC}"
        fi
        
        # Display current time
        echo -e "${GREEN}Current system time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${NC}"
    else
        echo -e "${RED}Time synchronization failed. Please check your network connection and try again.${NC}"
        return 1
    fi
}

# Misc menu
misc_menu() {
    while true; do
        echo -e "\n${BLUE}=== Misc Options ===${NC}"
        echo "1) Update and upgrade system"
        echo "2) Configure SSH"
        echo "3) Change hostname"
        echo "4) Install packages"
        echo "5) Sync system date/time"
        echo "6) Back to main menu"
        read -p "Choose option [1-6]: " misc_option
        
        case $misc_option in
            1) update_system ;;
            2) configure_ssh ;;
            3) change_hostname ;;
            4) install_packages_menu ;;
            5) sync_system_time ;;
            6) break ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
}

# Add new user
add_user() {
    read -p "Enter username: " username
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return 1
    fi
    
    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username already exists.${NC}"
        return 1
    fi
    
    # Create user
    useradd -m -s /bin/bash "$username" || {
        echo -e "${RED}Failed to create user.${NC}"
        return 1
    }
    
    # Set password
    echo "Setting password for $username:"
    passwd "$username"
    
    # Add to root group
    read -p "Add user to root group? [y/N]: " add_root
    if [[ "$add_root" =~ ^[Yy]$ ]]; then
        usermod -aG root "$username"
        echo -e "${GREEN}User added to root group.${NC}"
    fi
    
    # Sudo without password
    read -p "Allow sudo without password? [y/N]: " sudo_nopass
    if [[ "$sudo_nopass" =~ ^[Yy]$ ]]; then
        echo "$username ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/"$username"
        chmod 0440 /etc/sudoers.d/"$username"
        echo -e "${GREEN}Sudo without password enabled.${NC}"
    fi
    
    # Allow SSH
    read -p "Allow SSH access for this user? [y/N]: " allow_ssh
    if [[ "$allow_ssh" =~ ^[Yy]$ ]]; then
        # Ensure SSH directory exists
        local ssh_dir="/home/$username/.ssh"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown -R "$username:$username" "$ssh_dir"
        echo -e "${GREEN}SSH access enabled.${NC}"
    fi
    
    echo -e "${GREEN}User $username created successfully.${NC}"
}

# Add SSH key
add_ssh_key() {
    read -p "Enter username to add SSH key for: " username
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist.${NC}"
        return 1
    fi
    
    local home_dir
    if [ "$username" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$username"
    fi
    
    local ssh_dir="$home_dir/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    
    # Create .ssh directory if it doesn't exist
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"
    
    # Create authorized_keys if it doesn't exist
    if [ ! -f "$auth_keys" ]; then
        touch "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$username:$username" "$auth_keys"
    fi
    
    echo -e "${BLUE}Paste your SSH public key (single line):${NC}"
    read -r ssh_key
    
    if [ -z "$ssh_key" ]; then
        echo -e "${RED}SSH key cannot be empty.${NC}"
        return 1
    fi
    
    # Basic validation: check if it looks like an SSH key
    if [[ ! "$ssh_key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|ssh-dss) ]]; then
        echo -e "${YELLOW}Warning: This doesn't look like a standard SSH public key format.${NC}"
        read -p "Continue anyway? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Check if key already exists
    if grep -Fxq "$ssh_key" "$auth_keys"; then
        echo -e "${YELLOW}This SSH key already exists in authorized_keys.${NC}"
        return 0
    fi
    
    # Append key
    echo "$ssh_key" >> "$auth_keys"
    chmod 600 "$auth_keys"
    chown "$username:$username" "$auth_keys"
    
    echo -e "${GREEN}SSH key added successfully for user $username.${NC}"
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${BLUE}=== VPS Setup Script ===${NC}"
        echo "1) Misc (Update, SSH, Hostname, Packages)"
        echo "2) Add New User"
        echo "3) Add SSH Key"
        echo "4) Exit"
        read -p "Choose option [1-4]: " main_option
        
        case $main_option in
            1) misc_menu ;;
            2) add_user ;;
            3) add_ssh_key ;;
            4) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}VPS Setup Script${NC}"
    echo -e "${BLUE}Detecting OS...${NC}"
    detect_os
    echo -e "${GREEN}Detected OS: $OS_TYPE (Package Manager: $PKG_MANAGER)${NC}"
    
    main_menu
}

main "$@"
