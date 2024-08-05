#!/bin/bash

# Function to prompt for user input and validate non-empty value
prompt_for_value() {
    local prompt_message=$1
    local variable_name=$2
    local input_value=""
    while [ -z "$input_value" ]; do
        read -p "$prompt_message: " input_value
        if [ -z "$input_value" ]; then
            echo "Error: Value cannot be empty. Please try again."
        fi
    done
    eval $variable_name="'$input_value'"
}

# Create and navigate to the redmine directory
mkdir -p ~/redmine
cd ~/redmine

# Create the tools directory
mkdir -p tools

# Update system and install Docker, Docker Compose, and unzip
echo "Updating system and installing Docker, Docker Compose, and unzip..."

# Update package list
sudo apt update

# Install Docker, Docker Compose, and unzip
sudo apt install -y docker.io docker-compose-v2 unzip1

# Verify installations
docker --version
docker compose version


# Prompt for user input
echo "Welcome to the Redmine setup script!"
prompt_for_value "Enter the private IP address (e.g., 192.168.1.100)" PRIVATE_IP
prompt_for_value "Enter the Redmine database password" DB_PASSWORD
prompt_for_value "Enter the MySQL root password" MYSQL_ROOT_PASSWORD
prompt_for_value "Enter the Redmine MySQL user password" MYSQL_PASSWORD

# Debugging: Output values for verification
echo "Using the following values:"
echo "Private IP: $PRIVATE_IP"
echo "Redmine DB Password: $DB_PASSWORD"
echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
echo "MySQL User Password: $MYSQL_PASSWORD"

# Create self-signed SSL certificate
echo "Generating self-signed SSL certificate..."
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout certs/key.pem -out certs/cert.pem -subj "/CN=$PRIVATE_IP"

# Create docker-compose.yml
cat > docker-compose.yml <<EOL
version: '3.8'

services:
  redmine:
    image: redmine:latest
    container_name: redmine
    environment:
      - REDMINE_DB_MYSQL=mysql
      - REDMINE_DB_PASSWORD=${DB_PASSWORD}
      - REDMINE_DB_USERNAME=redmine
      - REDMINE_DB_DATABASE=redmine
      - REDMINE_DB_PORT=3306
    depends_on:
      mysql:
        condition: service_healthy
    ports:
      - "3000:3000"
    networks:
      - redmine_network
    volumes:
      - ./plugins:/usr/src/redmine/plugins
    restart: unless-stopped

  mysql:
    image: mysql:5.7
    container_name: mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: redmine
      MYSQL_USER: redmine
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - redmine_network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "--silent"]
      interval: 30s
      timeout: 10s
      retries: 5
    restart: unless-stopped

  nginx:
    image: nginx:latest
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/nginx/ssl
    depends_on:
      - redmine
    networks:
      - redmine_network
    restart: unless-stopped

volumes:
  mysql_data:

networks:
  redmine_network:
    driver: bridge
EOL

# Create nginx.conf
cat > nginx.conf <<EOL
user nginx;
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name $PRIVATE_IP;

        location / {
            proxy_pass http://redmine:3000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Redirect HTTP to HTTPS
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name $PRIVATE_IP;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256';
        ssl_prefer_server_ciphers on;

        location / {
            proxy_pass http://redmine:3000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOL

# Create the add_plugin script in ~/redmine/tools
cat > tools/add_plugin <<'EOL'
#!/bin/bash

# Function to prompt for user input and validate non-empty value
prompt_for_value() {
    local prompt_message=$1
    local variable_name=$2
    local input_value=""
    while [ -z "$input_value" ]; do
        read -p "$prompt_message: " input_value
        if [ -z "$input_value" ]; then
            echo "Error: Value cannot be empty. Please try again."
        fi
    done
    eval $variable_name="'$input_value'"
}

# Change to the tools directory
cd ~/redmine/tools

# Prompt for plugin details
echo "Redmine Plugin Installation Script"

# Prompt for the URL of the plugin zip file
prompt_for_value "Enter the URL of the plugin zip file (e.g., https://example.com/plugin.zip)" PLUGIN_URL

# Prompt for the name of the plugin directory
prompt_for_value "Enter the name of the plugin directory (e.g., redmine_checklists)" PLUGIN_DIR

# Download the plugin zip file
echo "Downloading the plugin zip file..."
wget "$PLUGIN_URL" -O "${PLUGIN_DIR}.zip"

# Unzip the plugin zip file
echo "Unzipping the plugin zip file..."
mkdir -p "$PLUGIN_DIR"
unzip "${PLUGIN_DIR}.zip" -d "$PLUGIN_DIR"

# Check if the Redmine container is running
if [ "$(docker ps -q -f name=redmine)" ]; then
    echo "Redmine container is running. Copying plugin to container..."
    # Copy the plugin to the Redmine container
    docker cp "$PLUGIN_DIR" redmine:/usr/src/redmine/plugins/

    # Verify plugin files inside the container
    echo "Verifying plugin files in container..."
    docker compose exec redmine ls /usr/src/redmine/plugins

    # Run the Redmine container command to migrate the database
    echo "Running Redmine database migration..."
    docker compose exec redmine rake redmine:plugins:migrate RAILS_ENV=production

    # Clear cache
    echo "Clearing Redmine cache..."
    docker compose exec redmine rake tmp:cache:clear RAILS_ENV=production

    # Check the result of the migration
    echo "Checking migration results..."
    docker compose exec redmine tail -n 20 /usr/src/redmine/log/production.log

    # Restart Redmine container to load the plugin
    echo "Restarting Redmine container..."
    docker compose restart redmine

    echo "Plugin added and Redmine restarted."
else
    echo "Error: Redmine container is not running. Please start the container first."
fi
EOL

# Make the add_plugin script executable
chmod +x tools/add_plugin

# Instructions for starting Docker Compose
echo "Docker Compose files created. You can start the services using the following command:"
echo "docker compose up -d"

# Prompt to start Docker Compose
read -p "Do you want to start Docker Compose now? (y/n): " START_DOCKER
if [[ $START_DOCKER == "y" ]]; then
    docker compose up -d
else
    echo "You can start Docker Compose later by running 'docker compose up -d'."
fi

echo "Setup complete."
