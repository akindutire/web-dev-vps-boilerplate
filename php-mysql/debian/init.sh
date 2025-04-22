#!/bin/bash

# Exit on error
set -e

echo "=== PHP & MySQL VPS Setup Script ==="
echo "-----------------------------------"

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# Ensure docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Install docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose not found. Installing docker-compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Setup UFW (Uncomplicated Firewall)
echo "Setting up UFW firewall..."
apt-get install -y ufw fail2ban

# Install fail2ban for auto-banning
echo "Configuring fail2ban for auto-banning..."
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

# Create custom filter for port scanning
cat > /etc/fail2ban/filter.d/ufw-port-scan.conf <<EOF
[Definition]
failregex = UFW BLOCK.* SRC=<HOST>
ignoreregex =
EOF

# Configure UFW
echo "Configuring UFW firewall rules..."
ufw default deny incoming
ufw default allow outgoing

# Allow specific ports
echo "Opening required ports (22, 80, 443, 3306)..."
ufw allow 22/tcp     # SSH
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
ufw allow 3306/tcp   # MySQL

# Enable UFW and restart fail2ban
echo "Enabling UFW and starting fail2ban..."
echo "y" | ufw enable
systemctl restart fail2ban



# Ask directory to store the project files
echo ""
read -p "Enter the project directory name (e.g., myproject):, project will be saved in /var/www " PROJECT_DIR
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="myproject"
    echo "Using default project name: $PROJECT_DIR"
fi

# Base directory
BASE_DIR="/var/www/$PROJECT_DIR"

# Setup directories
echo "Setting up directory structure in $BASE_DIR..."
mkdir -p "$BASE_DIR/dev/app"
mkdir -p "$BASE_DIR/live/app"
mkdir -p "$BASE_DIR/logs/nginx"
mkdir -p "$BASE_DIR/data/mysql"
mkdir -p "$BASE_DIR/data/mysql_bridge"
touch "$BASE_DIR/data/mysql_my.cnf"

# Install nginx on host
echo "Installing Nginx..."
apt-get update
apt-get install -y nginx

# Create Nginx site configuration
echo "Setting up Nginx configuration..."
echo ""
read -p "Enter the project url (e.g., myproject.com): " PROJECT_SITE
if [ -z "$PROJECT_SITE" ]; then
    PROJECT_SITE="myproject.com"
    echo "Using default project site: $PROJECT_DIR"
fi

# Creating mysql conf
echo "Creating mysql conf"
cat > "$BASE_DIR/data/mysql_my.cnf" <<EOF
[mysqld]
bind-address = 0.0.0.0
EOF

cat > "/etc/nginx/sites-available/$PROJECT_DIR" <<EOF
server {
    listen 80;
    server_name dev.$PROJECT_SITE;
    root $BASE_DIR/dev/app
    
    add_header X-Frame-Options \"SAMEORIGIN\" always; 
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;
    add_header Referrer-Policy \"strict-origin-only\" always;
    add_header Content-Security-Policy \"frame-ancestors 'self'\" always;

    add_header X-Served-By $server_name;
    add_header X-Request-Host $host;
    add_header Cache-Control \"no-cache\" always;
    add_header Pragma \"no-cache\" always;

    # Vary header to prevent proxy caching
    add_header Vary \"*\";

    # If using CloudFlare or similar:
    add_header CDN-Cache-Control \"no-cache\";

    client_max_body_size 30M;

    proxy_cache off;
    proxy_no_cache 1;

    index index.php;

    charset utf-8;

    # Prevent directory listing
    autoindex off;

    # Optional: Deny access to hidden files (like .env)
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    access_log $BASE_DIR/logs/nginx/dev-access.log;
    error_log $BASE_DIR/logs/nginx/dev-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:8005;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

}

server {
    listen 80;
    server_name $PROJECT_SITE;
    root $BASE_DIR/live/app
    
    add_header X-Frame-Options \"SAMEORIGIN\" always; 
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;
    add_header Referrer-Policy \"strict-origin-only\" always;
    add_header Content-Security-Policy \"frame-ancestors 'self'\" always;

    add_header X-Served-By $server_name;
    add_header X-Request-Host $host;
    add_header Cache-Control \"no-cache\" always;
    add_header Pragma \"no-cache\" always;

    # Vary header to prevent proxy caching
    add_header Vary \"*\";

    # If using CloudFlare or similar:
    add_header CDN-Cache-Control \"no-cache\";

    client_max_body_size 30M;

    proxy_cache off;
    proxy_no_cache 1;

    index index.php;

    charset utf-8;

    # Prevent directory listing
    autoindex off;

    # Optional: Deny access to hidden files (like .env)
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    access_log $BASE_DIR/logs/nginx/dev-access.log;
    error_log $BASE_DIR/logs/nginx/dev-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:8005;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

}

EOF

# Enable the site
ln -sf "/etc/nginx/sites-available/$PROJECT_DIR" "/etc/nginx/sites-enabled/"

# Test Nginx configuration
nginx -t

# Restart Nginx
systemctl restart nginx

# Create Docker Compose file
echo "Creating docker-compose.yml..."
cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  # PHP Service (Development)
  php_dev:
    image: php:8.2-fpm
    container_name: ${PROJECT_DIR}_php_dev
    restart: unless-stopped
    working_dir: /var/www/html
    volumes:
      - ${BASE_DIR}/dev/app:/var/www/html
    networks:
      - app_network
    ports:
      - "127.0.0.1:8005:9000"

  # PHP Service (Production)
  php_live:
    image: php:8.2-fpm
    container_name: ${PROJECT_DIR}_php_live
    restart: unless-stopped
    working_dir: /var/www/html
    volumes:
      - ${BASE_DIR}/live/app:/var/www/html
    networks:
      - app_network
    ports:
      - "127.0.0.1:8006:9000"

  # MySQL Service
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


# Create a sample PHP file
echo "Creating sample PHP files..."
cat > "$BASE_DIR/dev/app/index.php" <<EOF
<?php
phpinfo();
?>
EOF

cp "$BASE_DIR/dev/app/index.php" "$BASE_DIR/live/app/index.php"

# Set proper permissions
echo "Setting proper permissions..."
chown -R www-data:www-data "$BASE_DIR"
chmod -R 755 "$BASE_DIR"

# Start the Docker containers
echo "Starting Docker containers..."
cd "$BASE_DIR"
docker-compose up -d

echo ""
echo "=== Setup Complete ==="
echo "Development site: http://dev.$PROJECT_SITE"
echo "Production site: http://$PROJECT_SITE"
echo ""
echo "Don't forget to add these domains to your hosts file or DNS settings!"
echo "MySQL credentials:"
echo "  Host: localhost:3306"
echo "  Database: ${PROJECT_DIR}_main"
echo "  Username: ${PROJECT_DIR}"
echo "  Password: QrLiR1mz02njyeM"
echo ""
echo "Your PHP and MySQL environment is now ready!"