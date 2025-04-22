#!/bin/bash

# Exit on error
set -e

# === Colors ===
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

print_section() {
  echo -e "\n${BLUE}==> $1${RESET}\n"
}

print_warning() {
  echo -e "\n${YELLOW}[!] $1${RESET}"
}

print_success() {
  echo -e "\n${GREEN}[✔] $1${RESET}"
}

print_error() {
  echo -e "\n${RED}[✘] $1${RESET}"
}

print_info() {
  echo -e "\n${BLUE}[i] $1${RESET}"
}

print_section "🧹 PHP & MySQL VPS Teardown Script"

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
  print_error "This script must be run as root"
  exit 1
fi

# Ask for project directory name to teardown
print_info "Enter the project directory name to teardown (in /var/www):"
read -p "> " PROJECT_DIR
if [ -z "$PROJECT_DIR" ]; then
  print_error "Project directory name cannot be empty"
  exit 1
fi

# Confirm teardown
print_warning "This will completely remove the $PROJECT_DIR setup including:\n- All Docker containers and related volumes\n- All project files in /var/www/$PROJECT_DIR\n- Nginx configuration for $PROJECT_DIR"
read -p "Are you sure you want to proceed? (y/n): " CONFIRM
if [[ $CONFIRM != [yY] && $CONFIRM != [yY][eE][sS] ]]; then
  print_info "Teardown aborted."
  exit 0
fi

BASE_DIR="/var/www/$PROJECT_DIR"

print_section "📦 Stopping Docker Containers"
if [ -f "$BASE_DIR/docker-compose.yml" ]; then
  cd "$BASE_DIR"
  docker-compose down || true
fi

print_section "🧽 Removing Docker Volumes"
docker volume ls | grep -q "${PROJECT_DIR}_app_data" && docker volume rm "${PROJECT_DIR}_app_data" || true
docker volume ls | grep -q "${PROJECT_DIR}_mysql_data" && docker volume rm "${PROJECT_DIR}_mysql_data" || true

print_section "🗑️ Removing Nginx Configurations"
rm -f "/etc/nginx/sites-enabled/$PROJECT_DIR" || true
rm -f "/etc/nginx/sites-available/$PROJECT_DIR" || true

print_info "Restarting Nginx..."
systemctl restart nginx

print_section "🧹 Removing Project Directory"
rm -rf "$BASE_DIR" || true

print_success "Base resources for '$PROJECT_DIR' have been removed."

print_section "🛡️ Optional: Reset Security Configs"
read -p "Reset UFW and fail2ban configurations? (y/n): " RESET_SECURITY
if [[ $RESET_SECURITY == [yY] || $RESET_SECURITY == [yY][eE][sS] ]]; then
  print_info "Resetting UFW firewall rules..."
  ufw reset || true

  print_info "Removing custom fail2ban configurations..."
  rm -f "/etc/fail2ban/jail.local" || true
  rm -f "/etc/fail2ban/filter.d/ufw-port-scan.conf" || true

  systemctl restart fail2ban || true
  print_success "Security configurations reset."
fi

print_section "🧼 Optional: Remove Docker and Nginx"
read -p "Remove Docker and Nginx from the system? (y/n): " REMOVE_DEPS
if [[ $REMOVE_DEPS == [yY] || $REMOVE_DEPS == [yY][eE][sS] ]]; then
  print_info "Removing Docker..."
  apt-get purge -y docker-ce docker-ce-cli containerd.io || true
  apt-get autoremove -y || true
  rm -rf /var/lib/docker
  rm -f /usr/local/bin/docker-compose

  print_info "Removing Nginx..."
  apt-get purge -y nginx nginx-common || true
  apt-get autoremove -y || true

  print_success "Docker and Nginx have been removed."
fi

print_success "Teardown process completed successfully."
