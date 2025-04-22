#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Section header function
section() {
    echo -e "\n${BLUE}🔹 $1${NC}\n"
}

section "\n=== UBUNTU PHP & MySQL VPS Setup Script ===\n"

# Check if script is run as root
section "Checking Root Access"
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}✖ This script must be run as root${NC}"
    exit 1
else
    echo -e "${GREEN}✔ Running as root${NC}"
fi

# Ensure Docker is installed
section "Installing Docker"
if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Docker Compose plugin not found. Installing...${NC}"
    apt-get remove docker docker-engine docker.io containerd runc
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker’s official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
   

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
  
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable nginx
    systemctl start nginx
else
    echo -e "${GREEN}✔ Docker already installed${NC}"
fi

#  echo \
#       "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
#       https://download.docker.com/linux/debian bookworm stable" | \
#       tee /etc/apt/sources.list.d/docker.list > /dev/null

# Setup UFW and Fail2Ban
section "Installing and Configuring UFW & Fail2Ban"
apt-get install -y ufw fail2ban

# Configure Fail2Ban
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600

[ufw-port-scan]
enabled = true
filter = ufw-port-scan
logpath = /var/log/ufw.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

cat > /etc/fail2ban/filter.d/ufw-port-scan.conf <<EOF
[Definition]
failregex = UFW BLOCK.* SRC=<HOST>
ignoreregex =
EOF

# Configure UFW rules
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3306/tcp
echo "y" | ufw enable
systemctl enable fail2ban
systemctl restart fail2ban

# Ask for project directory
section "Project Directory Setup"
read -p "Enter the project directory name (e.g., myproject): " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-myproject}
echo -e "${GREEN}✔ Using project directory: $PROJECT_DIR${NC}"
BASE_DIR="/var/www/$PROJECT_DIR"
mkdir -p "$BASE_DIR/dev/app" "$BASE_DIR/live/app" "$BASE_DIR/logs/nginx" "$BASE_DIR/data/mysql" "$BASE_DIR/data/mysql_bridge"
touch "$BASE_DIR/data/mysql_my.cnf"

# Ask for project site
section "Project Domain Setup"
read -p "Enter the project domain (e.g., https://example.com/): " PROJECT_SITE_RAW
PROJECT_SITE=$(echo "$PROJECT_SITE_RAW" | sed -E 's~https?://~~;s~:.*~~;s~/.*~~;s~/*$~~')
PROJECT_SITE=${PROJECT_SITE:-myproject.com}
echo -e "${GREEN}✔ Using domain: $PROJECT_SITE${NC}"

# Install Nginx
section "Installing Nginx"
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx

# Create Nginx configuration
section "Creating Nginx Config"
cat > "/etc/nginx/sites-available/$PROJECT_DIR" <<EOF
server {
    listen 80;
    server_name dev.$PROJECT_SITE;
    root $BASE_DIR/dev/app;

    # Add all security headers together
    add_header X-Frame-Options "SAMEORIGIN" always; 
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-only" always;
    add_header Content-Security-Policy "frame-ancestors 'self'" always;
    add_header X-Served-By $server_name;
    add_header X-Request-Host $host;
    add_header Cache-Control "no-cache" always;
    add_header Pragma "no-cache" always;
    # Vary header to prevent proxy caching
    add_header Vary "*";
    # If using CloudFlare or similar:
    add_header CDN-Cache-Control "no-cache";
    
    proxy_cache off;
    proxy_no_cache 1;
    client_max_body_size 20M;
    
    index index.php;
    charset utf-8;
    autoindex off;
    access_log $BASE_DIR/logs/nginx/dev-access.log;
    error_log $BASE_DIR/logs/nginx/dev-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:8005;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}

server {
    listen 80;
    server_name $PROJECT_SITE;
    root $BASE_DIR/live/app;

    # Add all security headers together
    add_header X-Frame-Options "SAMEORIGIN" always; 
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-only" always;
    add_header Content-Security-Policy "frame-ancestors 'self'" always;
    add_header X-Served-By $server_name;
    add_header X-Request-Host $host;
    add_header Cache-Control "no-cache" always;
    add_header Pragma "no-cache" always;
    # Vary header to prevent proxy caching
    add_header Vary "*";
    # If using CloudFlare or similar:
    add_header CDN-Cache-Control "no-cache";
    
    proxy_cache off;
    proxy_no_cache 1;
    client_max_body_size 50M;

    index index.php;
    charset utf-8;
    autoindex off;
    access_log $BASE_DIR/logs/nginx/prod-access.log;
    error_log $BASE_DIR/logs/nginx/prod-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:8006;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

ln -sf "/etc/nginx/sites-available/$PROJECT_DIR" "/etc/nginx/sites-enabled/"
nginx -t
systemctl restart nginx

# MySQL config
cat > "$BASE_DIR/data/mysql_my.cnf" <<EOF
[mysqld]
bind-address = 0.0.0.0
EOF

# Docker Compose
section "Creating Docker Compose File"
cat > "$BASE_DIR/docker-compose.yml" <<EOF
services:
  php_dev:
    image: php:8.2-fpm
    container_name: ${PROJECT_DIR}_php_dev
    restart: unless-stopped
    working_dir: ${BASE_DIR}/dev/app
    volumes:
      - ${BASE_DIR}/dev/app:${BASE_DIR}/dev/app
    networks:
      - app_network
    ports:
      - "127.0.0.1:8005:9000"

  php_live:
    image: php:8.2-fpm
    container_name: ${PROJECT_DIR}_php_live
    restart: unless-stopped
    working_dir: ${BASE_DIR}/live/app
    volumes:
      - ${BASE_DIR}/live/app:${BASE_DIR}/live/app
    networks:
      - app_network
    ports:
      - "127.0.0.1:8006:9000"

  mysql:
    image: mysql:8.0
    container_name: ${PROJECT_DIR}_mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: vxPiR1mz
      MYSQL_DATABASE: ${PROJECT_DIR}_main
      MYSQL_USER: ${PROJECT_DIR}
      MYSQL_PASSWORD: QrLiR1mz02njyeM
    volumes:
      - ${BASE_DIR}/data/mysql:/var/lib/mysql
      - ${BASE_DIR}/data/mysql_bridge:/home
      - ${BASE_DIR}/data/mysql_my.cnf:/etc/mysql/conf.d/my.cnf
    networks:
      - app_network
    ports:
      - "3306:3306"

networks:
  app_network:
    driver: bridge
EOF

# Sample PHP file
section "Creating Sample PHP File"
echo "<?php phpinfo(); ?>" > "$BASE_DIR/dev/app/index.php"
cp "$BASE_DIR/dev/app/index.php" "$BASE_DIR/live/app/index.php"

# Set permissions
section "Setting File Permissions"
chown -R www-data:www-data "$BASE_DIR"
chmod -R 755 "$BASE_DIR"

# Start containers
section "Starting Docker Containers"
cd "$BASE_DIR"
docker-compose up -d

# Final message
echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "Development site: http://dev.$PROJECT_SITE"
echo -e "Production site: http://$PROJECT_SITE"
echo -e "\nMySQL Credentials:"
echo -e "  Host: localhost:3306"
echo -e "  Database: ${PROJECT_DIR}_main"
echo -e "  Username: ${PROJECT_DIR}"
echo -e "  Password: QrLiR1mz02njyeM"
echo -e "\nDon't forget to point your DNS or /etc/hosts to these domains!"
