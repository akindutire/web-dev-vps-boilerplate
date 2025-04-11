#!/bin/bash

# Exit on error
set -e

echo "=== PHP & MySQL VPS Teardown Script ==="
echo "--------------------------------------"

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# Ask for project directory name to teardown
echo ""
read -p "Enter the project directory name to teardown: " PROJECT_DIR
if [ -z "$PROJECT_DIR" ]; then
    echo "Project directory name cannot be empty"
    exit 1
fi

# Confirm teardown
echo ""
echo "WARNING: This will completely remove the $PROJECT_DIR setup including:"
echo "- All Docker containers and related volumes"
echo "- All project files in /var/www/$PROJECT_DIR"
echo "- Nginx configuration for $PROJECT_DIR"
echo ""
read -p "Are you sure you want to proceed? (y/n): " CONFIRM
if [[ $CONFIRM != [yY] && $CONFIRM != [yY][eE][sS] ]]; then
    echo "Teardown aborted."
    exit 0
fi

# Base directory
BASE_DIR="/var/www/$PROJECT_DIR"

# Stop and remove Docker containers
if [ -f "$BASE_DIR/docker-compose.yml" ]; then
    echo "Stopping and removing Docker containers..."
    cd "$BASE_DIR"
    docker-compose down
fi

# Remove Docker volumes
echo "Removing Docker volumes..."
if docker volume ls | grep -q "${PROJECT_DIR}_app_data"; then
    docker volume rm "${PROJECT_DIR}_app_data"
fi

if docker volume ls | grep -q "${PROJECT_DIR}_mysql_data"; then
    docker volume rm "${PROJECT_DIR}_mysql_data"
fi

# Remove Nginx configuration
echo "Removing Nginx configurations..."
if [ -f "/etc/nginx/sites-enabled/$PROJECT_DIR" ]; then
    rm -f "/etc/nginx/sites-enabled/$PROJECT_DIR"
fi

if [ -f "/etc/nginx/sites-available/$PROJECT_DIR" ]; then
    rm -f "/etc/nginx/sites-available/$PROJECT_DIR"
fi

# Restart Nginx
echo "Restarting Nginx..."
systemctl restart nginx

# Remove project directories
echo "Removing project directories..."
if [ -d "$BASE_DIR" ]; then
    rm -rf "$BASE_DIR"
fi

echo ""
echo "=== Teardown Complete ==="
echo "The following has been removed:"
echo "- Docker containers for $PROJECT_DIR"
echo "- Docker volumes: ${PROJECT_DIR}_app_data and ${PROJECT_DIR}_mysql_data"
echo "- Nginx configuration for $PROJECT_DIR"
echo "- Project directory: $BASE_DIR"
echo ""

# Ask if user wants to uninstall Docker and Nginx
echo "Do you want to remove Docker and Nginx as well?"
read -p "Remove Docker and Nginx? (y/n): " REMOVE_DEPS
if [[ $REMOVE_DEPS == [yY] || $REMOVE_DEPS == [yY][eE][sS] ]]; then
    echo "Removing Docker and Nginx..."
    
    # Remove Docker
    apt-get purge -y docker-ce docker-ce-cli containerd.io
    apt-get autoremove -y
    rm -rf /var/lib/docker
    rm -f /usr/local/bin/docker-compose
    
    # Remove Nginx
    apt-get purge -y nginx nginx-common
    apt-get autoremove -y
    
    echo "Docker and Nginx have been removed."
fi

echo ""
echo "Teardown process has completed successfully."