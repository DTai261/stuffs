# Print system information
print_system_info() {
    echo -e "${BLUE}=== System Information ===${NC}"

    # Hostname
    echo -e "${GREEN}Hostname:${NC} $(hostname)"

    # OS and kernel
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "${GREEN}OS:${NC} ${PRETTY_NAME:-$NAME}"
    fi
    echo -e "${GREEN}Kernel:${NC} $(uname -r)"

    # Uptime
    if command -v uptime &>/dev/null; then
        echo -e "${GREEN}Uptime:${NC} $(uptime -p 2>/dev/null || uptime)"
    fi

    # CPU info
    if command -v lscpu &>/dev/null; then
        local cpu_model
        cpu_model=$(lscpu | awk -F: '/Model name/ {gsub(/^ +/, "", $2); print $2; exit}')
        local cpu_cores
        cpu_cores=$(lscpu | awk -F: '/^CPU\\(s\\)/ {gsub(/^ +/, "", $2); print $2; exit}')
        [ -n "$cpu_model" ] && echo -e "${GREEN}CPU:${NC} $cpu_model"
        [ -n "$cpu_cores" ] && echo -e "${GREEN}CPU Cores:${NC} $cpu_cores"
    elif [ -f /proc/cpuinfo ]; then
        local cpu_model
        cpu_model=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{gsub(/^ +/, "", $2); print $2}')
        local cpu_cores
        cpu_cores=$(grep -c '^processor' /proc/cpuinfo)
        [ -n "$cpu_model" ] && echo -e "${GREEN}CPU:${NC} $cpu_model"
        [ -n "$cpu_cores" ] && echo -e "${GREEN}CPU Cores:${NC} $cpu_cores"
    fi

    # RAM info
    if command -v free &>/dev/null; then
        local mem_total mem_used mem_free
        read -r _ mem_total mem_used mem_free _ < <(free -m | awk '/^Mem:/ {print $1, $2, $3, $4}')
        echo -e "${GREEN}RAM Total:${NC} ${mem_total}MB"
        echo -e "${GREEN}RAM Used:${NC} ${mem_used}MB"
        echo -e "${GREEN}RAM Free:${NC} ${mem_free}MB"
    elif [ -f /proc/meminfo ]; then
        local mem_total_kb mem_free_kb
        mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        mem_free_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        if [ -n "$mem_total_kb" ]; then
            echo -e "${GREEN}RAM Total:${NC} $((mem_total_kb / 1024))MB"
        fi
        if [ -n "$mem_free_kb" ]; then
            echo -e "${GREEN}RAM Available:${NC} $((mem_free_kb / 1024))MB"
        fi
    fi

    # Disk usage for root filesystem
    if command -v df &>/dev/null; then
        local disk_info
        disk_info=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
        local disk_total disk_used disk_avail disk_use
        read -r disk_total disk_used disk_avail disk_use <<<"$disk_info"
        echo -e "${GREEN}Disk (root /):${NC} total=$disk_total, used=$disk_used, free=$disk_avail, use%=$disk_use"
    fi

    # IP addresses
    local ip_eth0=""
    local ip_primary=""

    if command -v ip &>/dev/null; then
        ip_eth0=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
        ip_primary=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    else
        ip_eth0=$(ifconfig eth0 2>/dev/null | awk '/inet / {print $2}' | head -1)
        ip_primary=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [ -n "$ip_eth0" ]; then
        echo -e "${GREEN}IP (eth0):${NC} $ip_eth0"
    else
        echo -e "${YELLOW}IP (eth0):${NC} not found or interface does not exist."
    fi

    if [ -n "$ip_primary" ] && [ "$ip_primary" != "$ip_eth0" ]; then
        echo -e "${GREEN}Primary IP:${NC} $ip_primary"
    fi

    # Public IP (optional)
    if command -v curl &>/dev/null; then
        local public_ip
        public_ip=$(curl -s --max-time 2 https://ifconfig.me 2>/dev/null || true)
        if [ -n "$public_ip" ]; then
            echo -e "${GREEN}Public IP:${NC} $public_ip"
        fi
    fi

    echo -e "${BLUE}=========================${NC}"
}
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

# Script directory (for relative paths like Configs/.tmux.conf)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

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

# Change system timezone
sync_system_time() {
    echo -e "${BLUE}Change System Timezone${NC}"
    echo -e "${YELLOW}Current timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || date +%Z 2>/dev/null || echo 'Unknown')${NC}"
    echo -e "${YELLOW}Current time: $(date)${NC}"
    echo ""
    
    # Common timezones with UTC offsets
    declare -A timezones=(
        ["1"]="UTC (UTC+0)"
        ["2"]="UTC+1 (Europe/Paris, Africa/Lagos)"
        ["3"]="UTC+2 (Europe/Athens, Africa/Cairo)"
        ["4"]="UTC+3 (Europe/Moscow, Africa/Nairobi)"
        ["5"]="UTC+4 (Asia/Dubai, Europe/Samara)"
        ["6"]="UTC+5 (Asia/Karachi, Asia/Tashkent)"
        ["7"]="UTC+6 (Asia/Dhaka, Asia/Almaty)"
        ["8"]="UTC+7 (Asia/Bangkok, Asia/Ho_Chi_Minh)"
        ["9"]="UTC+8 (Asia/Shanghai, Asia/Singapore)"
        ["10"]="UTC+9 (Asia/Tokyo, Asia/Seoul)"
        ["11"]="UTC+10 (Australia/Sydney, Pacific/Port_Moresby)"
        ["12"]="UTC+11 (Pacific/Norfolk, Pacific/Auckland)"
        ["13"]="UTC+12 (Pacific/Auckland, Pacific/Fiji)"
        ["14"]="UTC-1 (Atlantic/Azores)"
        ["15"]="UTC-2 (Atlantic/South_Georgia)"
        ["16"]="UTC-3 (America/Sao_Paulo, America/Argentina/Buenos_Aires)"
        ["17"]="UTC-4 (America/Caracas, America/Santiago)"
        ["18"]="UTC-5 (America/New_York, America/Bogota)"
        ["19"]="UTC-6 (America/Chicago, America/Mexico_City)"
        ["20"]="UTC-7 (America/Denver, America/Phoenix)"
        ["21"]="UTC-8 (America/Los_Angeles, America/Vancouver)"
        ["22"]="UTC-9 (America/Anchorage)"
        ["23"]="UTC-10 (Pacific/Honolulu)"
        ["24"]="UTC-11 (Pacific/Midway)"
        ["25"]="UTC-12 (Pacific/Baker_Island)"
    )
    
    # IANA timezone mappings for each UTC offset
    declare -A tz_mappings=(
        ["UTC"]="UTC"
        ["UTC+1"]="Europe/Paris"
        ["UTC+2"]="Europe/Athens"
        ["UTC+3"]="Europe/Moscow"
        ["UTC+4"]="Asia/Dubai"
        ["UTC+5"]="Asia/Karachi"
        ["UTC+6"]="Asia/Dhaka"
        ["UTC+7"]="Asia/Bangkok"
        ["UTC+8"]="Asia/Shanghai"
        ["UTC+9"]="Asia/Tokyo"
        ["UTC+10"]="Australia/Sydney"
        ["UTC+11"]="Pacific/Norfolk"
        ["UTC+12"]="Pacific/Auckland"
        ["UTC-1"]="Atlantic/Azores"
        ["UTC-2"]="Atlantic/South_Georgia"
        ["UTC-3"]="America/Sao_Paulo"
        ["UTC-4"]="America/Caracas"
        ["UTC-5"]="America/New_York"
        ["UTC-6"]="America/Chicago"
        ["UTC-7"]="America/Denver"
        ["UTC-8"]="America/Los_Angeles"
        ["UTC-9"]="America/Anchorage"
        ["UTC-10"]="Pacific/Honolulu"
        ["UTC-11"]="Pacific/Midway"
        ["UTC-12"]="Pacific/Baker_Island"
    )
    
    echo -e "${BLUE}Select timezone:${NC}"
    for i in {1..25}; do
        echo "$i) ${timezones[$i]}"
    done
    echo "26) Custom timezone (enter IANA timezone name)"
    echo "27) Cancel"
    
    read -p "Choose option [1-27]: " tz_option
    
    local selected_tz=""
    local tz_display=""
    
    case $tz_option in
        1)
            selected_tz="UTC"
            tz_display="UTC (UTC+0)"
            ;;
        2)
            selected_tz="Europe/Paris"
            tz_display="UTC+1"
            ;;
        3)
            selected_tz="Europe/Athens"
            tz_display="UTC+2"
            ;;
        4)
            selected_tz="Europe/Moscow"
            tz_display="UTC+3"
            ;;
        5)
            selected_tz="Asia/Dubai"
            tz_display="UTC+4"
            ;;
        6)
            selected_tz="Asia/Karachi"
            tz_display="UTC+5"
            ;;
        7)
            selected_tz="Asia/Dhaka"
            tz_display="UTC+6"
            ;;
        8)
            selected_tz="Asia/Bangkok"
            tz_display="UTC+7"
            ;;
        9)
            selected_tz="Asia/Shanghai"
            tz_display="UTC+8"
            ;;
        10)
            selected_tz="Asia/Tokyo"
            tz_display="UTC+9"
            ;;
        11)
            selected_tz="Australia/Sydney"
            tz_display="UTC+10"
            ;;
        12)
            selected_tz="Pacific/Norfolk"
            tz_display="UTC+11"
            ;;
        13)
            selected_tz="Pacific/Auckland"
            tz_display="UTC+12"
            ;;
        14)
            selected_tz="Atlantic/Azores"
            tz_display="UTC-1"
            ;;
        15)
            selected_tz="Atlantic/South_Georgia"
            tz_display="UTC-2"
            ;;
        16)
            selected_tz="America/Sao_Paulo"
            tz_display="UTC-3"
            ;;
        17)
            selected_tz="America/Caracas"
            tz_display="UTC-4"
            ;;
        18)
            selected_tz="America/New_York"
            tz_display="UTC-5"
            ;;
        19)
            selected_tz="America/Chicago"
            tz_display="UTC-6"
            ;;
        20)
            selected_tz="America/Denver"
            tz_display="UTC-7"
            ;;
        21)
            selected_tz="America/Los_Angeles"
            tz_display="UTC-8"
            ;;
        22)
            selected_tz="America/Anchorage"
            tz_display="UTC-9"
            ;;
        23)
            selected_tz="Pacific/Honolulu"
            tz_display="UTC-10"
            ;;
        24)
            selected_tz="Pacific/Midway"
            tz_display="UTC-11"
            ;;
        25)
            selected_tz="Pacific/Baker_Island"
            tz_display="UTC-12"
            ;;
        26)
            read -p "Enter IANA timezone name (e.g., America/New_York, Europe/London): " selected_tz
            if [ -z "$selected_tz" ]; then
                echo -e "${RED}Timezone cannot be empty.${NC}"
                return 1
            fi
            tz_display="$selected_tz"
            ;;
        27)
            echo -e "${YELLOW}Cancelled.${NC}"
            return 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            return 1
            ;;
    esac
    
    # Verify timezone exists
    if [ ! -f "/usr/share/zoneinfo/$selected_tz" ] && [ "$selected_tz" != "UTC" ]; then
        echo -e "${RED}Invalid timezone: $selected_tz${NC}"
        echo -e "${YELLOW}Please check the IANA timezone name and try again.${NC}"
        return 1
    fi
    
    # Set timezone
    echo -e "${BLUE}Setting timezone to $selected_tz ($tz_display)...${NC}"
    
    if command -v timedatectl &> /dev/null; then
        if timedatectl set-timezone "$selected_tz" 2>/dev/null; then
            echo -e "${GREEN}Timezone set to $selected_tz ($tz_display)${NC}"
        else
            echo -e "${RED}Failed to set timezone using timedatectl.${NC}"
            return 1
        fi
    else
        # Fallback method: update /etc/localtime
        if [ -f "/usr/share/zoneinfo/$selected_tz" ]; then
            if [ -f /etc/localtime ]; then
                backup_file "/etc/localtime"
            fi
            if ln -sf "/usr/share/zoneinfo/$selected_tz" /etc/localtime 2>/dev/null; then
                echo -e "${GREEN}Timezone set to $selected_tz ($tz_display)${NC}"
            else
                echo -e "${RED}Failed to set timezone.${NC}"
                return 1
            fi
        elif [ "$selected_tz" = "UTC" ]; then
            if [ -f /etc/localtime ]; then
                backup_file "/etc/localtime"
            fi
            if ln -sf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null; then
                echo -e "${GREEN}Timezone set to UTC${NC}"
            else
                echo -e "${RED}Failed to set timezone.${NC}"
                return 1
            fi
        else
            echo -e "${RED}Timezone file not found: /usr/share/zoneinfo/$selected_tz${NC}"
            return 1
        fi
    fi
    
    # Display updated time
    echo -e "${GREEN}Current system time: $(date)${NC}"
    echo -e "${GREEN}Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || date +%Z 2>/dev/null || echo "$selected_tz")${NC}"
    
    # Ask if user wants to sync time
    echo ""
    read -p "Do you want to sync system time with NTP? [y/N]: " sync_choice
    if [[ "$sync_choice" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Syncing system time...${NC}"
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
        
        if [ $time_synced -eq 1 ]; then
            # Display current time
            echo -e "${GREEN}Time synchronized successfully.${NC}"
            echo -e "${GREEN}Current system time: $(date)${NC}"
        else
            echo -e "${YELLOW}Time synchronization failed, but timezone has been set.${NC}"
            echo -e "${GREEN}Current system time: $(date)${NC}"
        fi
    else
        echo -e "${BLUE}Skipping time synchronization.${NC}"
    fi
}

# Configure tmux for a specific user
configure_tmux() {
    read -p "Enter username to configure tmux for: " username

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

    # Ensure tmux and git are installed
    install_package "tmux"
    install_package "git"

    # Install TPM (Tmux Plugin Manager) for this user
    local tpm_dir="$home_dir/.tmux/plugins/tpm"
    if [ -d "$tpm_dir/.git" ]; then
        echo -e "${YELLOW}TPM already installed for user $username.${NC}"
    else
        echo -e "${BLUE}Cloning TPM for user $username...${NC}"
        sudo -u "$username" git clone https://github.com/tmux-plugins/tpm "$tpm_dir" 2>/dev/null || {
            echo -e "${RED}Failed to clone TPM for user $username.${NC}"
        }
    fi

    # Source config template from script directory
    local config_src="$SCRIPT_DIR/Configs/.tmux.conf"
    if [ ! -f "$config_src" ]; then
        echo -e "${RED}Tmux config template not found at $config_src${NC}"
        return 1
    fi

    local tmux_conf="$home_dir/.tmux.conf"

    # Backup existing tmux.conf if present (move to .bak as requested)
    if [ -f "$tmux_conf" ]; then
        local backup_path="$tmux_conf.bak"
        if [ -f "$backup_path" ]; then
            backup_path="${tmux_conf}.bak_$(date +%d%m%y)"
        fi
        mv "$tmux_conf" "$backup_path"
        echo -e "${GREEN}Existing tmux config moved to $backup_path${NC}"
    fi

    # Copy new config
    cp "$config_src" "$tmux_conf"
    chown "$username:$username" "$tmux_conf"
    chmod 644 "$tmux_conf"
    echo -e "${GREEN}Tmux config applied for user $username.${NC}"

    # Reload tmux config if the user has an active tmux session
    if sudo -u "$username" tmux list-sessions >/dev/null 2>&1; then
        sudo -u "$username" tmux source-file "$tmux_conf" >/dev/null 2>&1 && \
        sudo -u "$username" tmux display-message "tmux config reloaded" >/dev/null 2>&1
        echo -e "${GREEN}Tmux configuration reloaded for user $username.${NC}"
    else
        echo -e "${YELLOW}No active tmux session found for user $username. Config will be used next time tmux starts.${NC}"
    fi
}

# Change user password
change_user_password() {
    read -p "Enter username to change password for: " username

    if [ -z "$username" ]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return 1
    fi

    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist.${NC}"
        return 1
    fi

    while true; do
        read -s -p "Enter new password for $username: " pass1
        echo ""
        read -s -p "Confirm new password: " pass2
        echo ""

        if [ "$pass1" = "$pass2" ]; then
            if [ -z "$pass1" ]; then
                echo -e "${RED}Password cannot be empty.${NC}"
                continue
            fi
            echo "$username:$pass1" | chpasswd
            echo -e "${GREEN}Password for user $username changed successfully.${NC}"
            break
        else
            echo -e "${RED}Passwords do not match. Please try again.${NC}"
        fi
    done
}

# Install WordPress with Docker
install_wordpress() {
    echo -e "${BLUE}=== WordPress Installation ===${NC}"
    
    # Get domain from user
    read -p "Enter domain name (leave empty for localhost): " domain_name
    
    # Set default to localhost if empty
    if [ -z "$domain_name" ]; then
        domain_name="localhost"
        echo -e "${YELLOW}No domain provided. Using localhost.${NC}"
    fi
    
    # Check and install Docker
    echo -e "${BLUE}Checking Docker...${NC}"
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}Docker not found. Installing...${NC}"
        case $PKG_MANAGER in
            apt)
                $UPDATE_CMD
                $INSTALL_CMD ca-certificates curl gnupg
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
                $UPDATE_CMD
                $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
            yum|dnf)
                $INSTALL_CMD -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
            pacman)
                $INSTALL_CMD docker docker-compose
                ;;
        esac
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}Docker installed successfully.${NC}"
    else
        echo -e "${GREEN}Docker is already installed.${NC}"
    fi
    
    # Check and install Nginx
    echo -e "${BLUE}Checking Nginx...${NC}"
    if ! command -v nginx &>/dev/null; then
        echo -e "${YELLOW}Nginx not found. Installing...${NC}"
        install_package "nginx"
        systemctl enable nginx
        systemctl start nginx
        echo -e "${GREEN}Nginx installed successfully.${NC}"
    else
        echo -e "${GREEN}Nginx is already installed.${NC}"
    fi
    
    # Check and install docker-compose
    echo -e "${BLUE}Checking docker-compose...${NC}"
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        echo -e "${YELLOW}Docker Compose not found. Installing...${NC}"
        case $PKG_MANAGER in
            apt)
                $INSTALL_CMD docker-compose-plugin
                ;;
            yum|dnf)
                $INSTALL_CMD docker-compose-plugin
                ;;
            pacman)
                $INSTALL_CMD docker-compose
                ;;
        esac
        echo -e "${GREEN}Docker Compose installed successfully.${NC}"
    else
        echo -e "${GREEN}Docker Compose is already installed.${NC}"
    fi
    
    # Setup WordPress directory
    local wp_dir="/opt/wordpress"
    echo -e "${BLUE}Setting up WordPress in $wp_dir...${NC}"
    
    if [ -d "$wp_dir" ]; then
        echo -e "${YELLOW}Directory $wp_dir already exists.${NC}"
        read -p "Do you want to overwrite existing installation? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Installation cancelled.${NC}"
            return 1
        fi
        backup_file "$wp_dir/docker-compose.yml" 2>/dev/null || true
        backup_file "$wp_dir/.env" 2>/dev/null || true
    else
        mkdir -p "$wp_dir"
    fi
    
    # Create directory structure
    mkdir -p "$wp_dir/wordpress"
    mkdir -p "$wp_dir/db"
    mkdir -p "$wp_dir/nginx/conf.d"
    mkdir -p "$wp_dir/nginx/certs"
    mkdir -p "$wp_dir/nginx/logs"
    
    # Copy docker-compose.yml from Configs
    local config_src="$SCRIPT_DIR/Configs/wordpress/docker-compose.yml"
    if [ ! -f "$config_src" ]; then
        echo -e "${RED}WordPress docker-compose template not found at $config_src${NC}"
        return 1
    fi
    
    cp "$config_src" "$wp_dir/docker-compose.yml"
    
    # Copy and update .env file
    local env_src="$SCRIPT_DIR/Configs/wordpress/.env"
    if [ ! -f "$env_src" ]; then
        echo -e "${RED}WordPress .env template not found at $env_src${NC}"
        return 1
    fi
    
    cp "$env_src" "$wp_dir/.env"
    
    # Prompt for database credentials
    echo -e "${BLUE}Configure database credentials:${NC}"
    read -p "Database name [wordpress]: " db_name
    db_name=${db_name:-wordpress}
    
    read -p "Database user [wp_user]: " db_user
    db_user=${db_user:-wp_user}
    
    read -s -p "Database password (leave empty for auto-generated): " db_pass
    echo ""
    if [ -z "$db_pass" ]; then
        db_pass=$(openssl rand -base64 32 2>/dev/null || tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)
        echo -e "${GREEN}Generated password: $db_pass${NC}"
    fi
    
    read -s -p "Database root password (leave empty for auto-generated): " db_root_pass
    echo ""
    if [ -z "$db_root_pass" ]; then
        db_root_pass=$(openssl rand -base64 32 2>/dev/null || tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)
        echo -e "${GREEN}Generated root password: $db_root_pass${NC}"
    fi
    
    # Prompt for WordPress admin account
    echo ""
    echo -e "${BLUE}Configure WordPress admin account:${NC}"
    read -p "Site title [My WordPress Site]: " wp_title
    wp_title=${wp_title:-My WordPress Site}
    
    read -p "Admin username [admin]: " wp_admin_user
    wp_admin_user=${wp_admin_user:-admin}
    
    # Validate admin username (should not be 'admin' for security, but allow it)
    if [ "$wp_admin_user" = "admin" ]; then
        echo -e "${YELLOW}Warning: Using 'admin' as username is not recommended for security.${NC}"
        read -p "Continue with 'admin'? [Y/n]: " confirm_admin
        if [[ "$confirm_admin" =~ ^[Nn]$ ]]; then
            read -p "Enter admin username: " wp_admin_user
            wp_admin_user=${wp_admin_user:-admin}
        fi
    fi
    
    # Get admin password with confirmation
    while true; do
        read -s -p "Admin password (leave empty for auto-generated): " wp_admin_pass
        echo ""
        if [ -z "$wp_admin_pass" ]; then
            wp_admin_pass=$(openssl rand -base64 32 2>/dev/null || tr -dc 'a-zA-Z0-9!@#$%^&*' < /dev/urandom | head -c 24)
            echo -e "${GREEN}Generated admin password: $wp_admin_pass${NC}"
            break
        else
            read -s -p "Confirm admin password: " wp_admin_pass_confirm
            echo ""
            if [ "$wp_admin_pass" = "$wp_admin_pass_confirm" ]; then
                break
            else
                echo -e "${RED}Passwords do not match. Please try again.${NC}"
            fi
        fi
    done
    
    # Get admin email
    while true; do
        read -p "Admin email: " wp_admin_email
        if [ -z "$wp_admin_email" ]; then
            echo -e "${RED}Admin email is required.${NC}"
        elif [[ ! "$wp_admin_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            echo -e "${RED}Invalid email format. Please try again.${NC}"
        else
            break
        fi
    done
    
    # Update .env file
    cat > "$wp_dir/.env" << EOF
MYSQL_DATABASE=$db_name
MYSQL_USER=$db_user
MYSQL_PASSWORD=$db_pass
MYSQL_ROOT_PASSWORD=$db_root_pass
EOF
    
    # Copy and configure nginx
    local nginx_src="$SCRIPT_DIR/Configs/wordpress/wordpress.conf"
    if [ ! -f "$nginx_src" ]; then
        echo -e "${RED}WordPress nginx config template not found at $nginx_src${NC}"
        return 1
    fi
    
    # Copy nginx config to WordPress directory
    cp "$nginx_src" "$wp_dir/nginx/conf.d/wordpress.conf"
    
    # Also update docker-compose.yml to use the domain
    sed -i "s/www\.example\.com/$domain_name/g" "$wp_dir/docker-compose.yml"
    
    # Set permissions
    chown -R root:root "$wp_dir"
    chmod 600 "$wp_dir/.env"
    
    echo -e "${GREEN}WordPress configuration files prepared.${NC}"
    echo -e "${BLUE}Starting WordPress containers...${NC}"
    
    # Start containers
    cd "$wp_dir"
    local compose_cmd=""
    
    # Determine which docker compose command to use
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    elif docker-compose version &>/dev/null; then
        compose_cmd="docker-compose"
    else
        echo -e "${RED}Neither 'docker compose' nor 'docker-compose' is available.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Using: $compose_cmd${NC}"
    
    # Stop and remove any existing containers to ensure clean start
    echo -e "${BLUE}Cleaning up any existing containers...${NC}"
    $compose_cmd down --remove-orphans 2>/dev/null || true
    
    # Remove any existing WordPress containers that might be stuck
    docker rm -f wp_db wp_app wp_nginx 2>/dev/null || true
    
    # Check if database directory exists and may have corrupted files
    if [ -d "$wp_dir/db" ] && [ "$(ls -A $wp_dir/db 2>/dev/null)" ]; then
        echo -e "${YELLOW}Existing database directory found. It may contain corrupted data from a previous failed start.${NC}"
        read -p "Do you want to remove the existing database and start fresh? [y/N]: " clean_db
        if [[ "$clean_db" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Removing existing database directory...${NC}"
            rm -rf "$wp_dir/db"/*
            rm -rf "$wp_dir/db"/.* 2>/dev/null || true
            echo -e "${GREEN}Database directory cleaned.${NC}"
        else
            echo -e "${YELLOW}Keeping existing database. Note: If the database is corrupted, the container will fail to start.${NC}"
        fi
    fi
    
    # Pull latest images
    echo -e "${BLUE}Pulling latest Docker images...${NC}"
    $compose_cmd pull
    
    # Stop system Nginx to free up port 80/443 for Docker Nginx
    echo -e "${BLUE}Stopping system Nginx to allow Docker Nginx to use port 80/443...${NC}"
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    
    # Also stop any other service using port 80
    if command -v fuser &>/dev/null; then
        fuser -k 80/tcp 2>/dev/null || true
    fi
    
    echo -e "${GREEN}System Nginx stopped. Docker Nginx will handle port 80/443.${NC}"
    
    # Start containers
    echo -e "${BLUE}Starting containers...${NC}"
    if $compose_cmd up -d; then
        echo -e "${GREEN}WordPress containers started.${NC}"
    else
        echo -e "${RED}Failed to start WordPress containers.${NC}"
        echo -e "${YELLOW}Checking container logs...${NC}"
        $compose_cmd logs --tail 50
        return 1
    fi
    
    # Wait for containers to be healthy
    echo -e "${BLUE}Waiting for containers to be ready...${NC}"
    sleep 15
    
    # Check container status with detailed output
    echo -e "${BLUE}Checking container status...${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "wp_db|wp_app|wp_nginx|NAMES"
    
    # Check if all containers are running
    local all_running=true
    for container in wp_db wp_app wp_nginx; do
        local container_status
        container_status=$(docker ps --filter "name=$container" --format "{{.Status}}" 2>/dev/null)
        if [ -z "$container_status" ]; then
            echo -e "${RED}Container $container is not running!${NC}"
            all_running=false
        else
            echo -e "${GREEN}Container $container: $container_status${NC}"
        fi
    done
    
    if [ "$all_running" = true ]; then
        echo -e "${GREEN}All containers are running.${NC}"
    else
        echo -e "${YELLOW}Some containers are not running. Attempting restart...${NC}"
        $compose_cmd restart
        sleep 10
        
        # Check again
        local retry_ok=true
        for container in wp_db wp_app wp_nginx; do
            if ! docker ps | grep -q "$container"; then
                echo -e "${RED}Container $container still not running!${NC}"
                echo -e "${YELLOW}Logs for $container:${NC}"
                docker logs --tail 20 "$container" 2>&1 || true
                retry_ok=false
            fi
        done
        
        if [ "$retry_ok" != true ]; then
            echo -e "${RED}Some containers failed to start.${NC}"
            echo ""
            echo -e "${YELLOW}Checking container exit reasons...${NC}"
            for container in wp_db wp_app wp_nginx; do
                local exit_code
                exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$container" 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}$container exit code: $exit_code${NC}"
                if [ "$exit_code" != "0" ] && [ "$exit_code" != "unknown" ]; then
                    echo -e "${YELLOW}Last 30 lines of $container logs:${NC}"
                    docker logs --tail 30 "$container" 2>&1 || true
                    echo ""
                fi
            done
            return 1
        fi
        echo -e "${GREEN}All containers are now running.${NC}"
    fi
    
    # Install WP-CLI and configure WordPress
    echo -e "${BLUE}Installing WP-CLI and configuring WordPress...${NC}"
    
    # Wait for database to be ready
    echo -e "${BLUE}Waiting for database to be ready...${NC}"
    local db_ready=0
    local db_retries=0
    while [ $db_ready -eq 0 ] && [ $db_retries -lt 30 ]; do
        if docker exec wp_db mariadb-admin ping -h localhost -u root -p"$db_root_pass" --silent 2>/dev/null; then
            db_ready=1
        else
            sleep 2
            db_retries=$((db_retries + 1))
            echo -n "."
        fi
    done
    echo ""
    
    if [ $db_ready -eq 0 ]; then
        echo -e "${YELLOW}Database may not be ready yet. WordPress installation will need to be completed manually.${NC}"
    else
        echo -e "${GREEN}Database is ready.${NC}"
        
        # Install WP-CLI in the WordPress container
        echo -e "${BLUE}Installing WP-CLI...${NC}"
        docker exec wp_app bash -c "
            curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
            chmod +x wp-cli.phar && \
            mv wp-cli.phar /usr/local/bin/wp
        " 2>/dev/null
        
        if docker exec wp_app wp --version &>/dev/null; then
            echo -e "${GREEN}WP-CLI installed successfully.${NC}"
            
            # Wait for WordPress files to be ready
            sleep 5
            
            # Create wp-config.php if it doesn't exist
            if ! docker exec wp_app test -f /var/www/html/wp-config.php 2>/dev/null; then
                echo -e "${BLUE}Creating wp-config.php...${NC}"
                docker exec wp_app wp config create \
                    --dbname="$db_name" \
                    --dbuser="$db_user" \
                    --dbpass="$db_pass" \
                    --dbhost="db:3306" \
                    --allow-root 2>/dev/null || true
            fi
            
            # Check if WordPress is already installed
            local wp_installed=0
            if docker exec wp_app wp core is-installed --allow-root 2>/dev/null; then
                wp_installed=1
            fi
            
            if [ $wp_installed -eq 0 ]; then
                echo -e "${BLUE}Installing WordPress...${NC}"
                
                # Determine protocol based on domain
                local wp_url
                if [ "$domain_name" = "localhost" ]; then
                    wp_url="http://localhost"
                else
                    wp_url="https://$domain_name"
                fi
                
                # Install WordPress with admin account
                if docker exec wp_app wp core install \
                    --url="$wp_url" \
                    --title="$wp_title" \
                    --admin_user="$wp_admin_user" \
                    --admin_password="$wp_admin_pass" \
                    --admin_email="$wp_admin_email" \
                    --allow-root 2>/dev/null; then
                    echo -e "${GREEN}WordPress installed successfully!${NC}"
                    wp_installed=1
                else
                    echo -e "${YELLOW}WordPress core installation may have failed or already exists.${NC}"
                fi
            else
                echo -e "${YELLOW}WordPress is already installed.${NC}"
                wp_installed=1
            fi
            
            # Store installation status for final output
            local wp_install_success=$wp_installed
        else
            echo -e "${YELLOW}WP-CLI installation failed. WordPress will need to be configured manually.${NC}"
            local wp_install_success=0
        fi
    fi
    
    echo ""
    echo -e "${GREEN}=== WordPress Installation Complete ===${NC}"
    echo -e "${GREEN}Domain:${NC} $domain_name"
    echo -e "${GREEN}Site Title:${NC} $wp_title"
    echo -e "${GREEN}Directory:${NC} $wp_dir"
    echo -e "${GREEN}Database:${NC} $db_name"
    echo -e "${GREEN}Database User:${NC} $db_user"
    
    if [ "$domain_name" = "localhost" ]; then
        echo -e "${GREEN}Access URL:${NC} http://localhost"
        local wp_admin_url="http://localhost/wp-admin"
    else
        echo -e "${GREEN}Access URL:${NC} https://$domain_name"
        local wp_admin_url="https://$domain_name/wp-admin"
    fi
    
    echo ""
    echo -e "${BLUE}=== Admin Account ===${NC}"
    echo -e "${GREEN}Username:${NC} $wp_admin_user"
    echo -e "${GREEN}Password:${NC} $wp_admin_pass"
    echo -e "${GREEN}Email:${NC} $wp_admin_email"
    echo -e "${GREEN}Admin URL:${NC} $wp_admin_url"
    
    echo ""
    if [ "${wp_install_success:-0}" = "1" ]; then
        echo -e "${GREEN}WordPress has been automatically configured and is ready to use!${NC}"
    else
        echo -e "${YELLOW}Note: WordPress may need manual setup. Visit the URL above to complete installation.${NC}"
    fi
    echo -e "${YELLOW}Database credentials are stored in:${NC} $wp_dir/.env"
    echo -e "${YELLOW}To manage containers:${NC} cd $wp_dir && $compose_cmd up -d"
    echo ""
    echo -e "${BLUE}=== Cloudflare Configuration ===${NC}"
    echo -e "${YELLOW}1. Set Cloudflare SSL/TLS encryption mode to:${NC} Full"
    echo -e "${YELLOW}2. Ensure DNS records point to your VPS IP${NC}"
    echo -e "${YELLOW}3. If using HTTPS, configure SSL certificates in:${NC} $wp_dir/nginx/certs/"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Save the admin credentials above. They will not be shown again!${NC}"
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
        echo "6) Configure Tmux"
        echo "7) Change user password"
        echo "8) Install WordPress"
        echo "9) Back to main menu"
        read -p "Choose option [1-9]: " misc_option
        
        case $misc_option in
            1) update_system ;;
            2) configure_ssh ;;
            3) change_hostname ;;
            4) install_packages_menu ;;
            5) sync_system_time ;;
            6) configure_tmux ;;
            7) change_user_password ;;
            8) install_wordpress ;;
            9) break ;;
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

    # Show basic system information
    print_system_info
    
    main_menu
}

main "$@"
