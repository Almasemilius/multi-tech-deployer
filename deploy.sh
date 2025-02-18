#!/bin/bash

# Function to display a simple header
display_header() {
    echo "================================================="
    echo "          Automatic Deployment Script            "
    echo "================================================="
    echo
}

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local var_name="$2"
    local validation_func="$3"
    
    while true; do
        read -p "$prompt: " input
        if [[ -z "$input" ]]; then
            echo "Input cannot be empty. Please try again."
        elif [[ -n "$validation_func" ]] && ! $validation_func "$input"; then
            # Skip this if no validation function provided
            continue
        else
            eval "$var_name='$input'"
            break
        fi
    done
}

# Function to validate git repository URL
validate_repo_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://.*\.git$ ]] || [[ "$url" =~ ^git@.*:.*/.*\.git$ ]]; then
        return 0
    else
        echo "Invalid git repository URL. It should end with .git"
        return 1
    fi
}

# Function to set up Node.js application
setup_nodejs() {
    echo "Setting up Node.js application..."
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Clone the repository
    git clone "$repo_url" .
    
    # Install dependencies
    echo "Installing dependencies..."
    npm install
    
    # Check if PM2 is installed, install if not
    if ! command -v pm2 &> /dev/null; then
        echo "Installing PM2 for process management..."
        npm install -g pm2
    fi
    
    # Look for package.json to determine start command
    if [ -f "package.json" ]; then
        # Check for start script in package.json
        start_command=$(grep -o '"start": *"[^"]*"' package.json | cut -d'"' -f4)
        
        if [ -z "$start_command" ]; then
            # If no start script, check for main file
            main_file=$(grep -o '"main": *"[^"]*"' package.json | cut -d'"' -f4)
            if [ -n "$main_file" ]; then
                start_command="node $main_file"
            else
                # Default to index.js if no main specified
                start_command="node index.js"
            fi
        else
            # If start script exists, use npm start
            start_command="npm start"
        fi
    else
        # Default fallback
        start_command="node index.js"
    fi
    
    # Start the application with PM2
    echo "Starting application with PM2..."
    pm2 start "$start_command" --name "$app_name"
    
    echo "Application deployed successfully!"
}

# Function to set up Python application
setup_python() {
    echo "Setting up Python application..."
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Clone the repository
    git clone "$repo_url" .
    
    # Create and activate virtual environment
    echo "Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    
    # Install requirements
    if [ -f "requirements.txt" ]; then
        echo "Installing dependencies from requirements.txt..."
        pip install -r requirements.txt
    else
        echo "No requirements.txt found. Skipping dependency installation."
    fi
    
    # Try to detect the main application file
    if [ -f "app.py" ]; then
        app_file="app.py"
    elif [ -f "main.py" ]; then
        app_file="main.py"
    elif [ -f "wsgi.py" ]; then
        app_file="wsgi.py"
    else
        # Prompt for the main file if not found
        get_input "Main Python file not detected. Please specify the main file" app_file
    fi
    
    # Set up Gunicorn for WSGI applications or use basic Python for scripts
    if grep -q "Flask\|Django\|FastAPI" requirements.txt 2>/dev/null; then
        echo "Detected web framework, setting up with Gunicorn..."
        pip install gunicorn
        
        # Check if it's a Flask app
        if grep -q "Flask" requirements.txt; then
            app_module="${app_file%.*}:app"  # Assumes Flask app instance is named 'app'
        # Check if it's a Django app
        elif grep -q "Django" requirements.txt; then
            app_module="${app_file%.*}:application"  # Django WSGI application
        # Otherwise assume a generic WSGI app
        else
            app_module="${app_file%.*}:app"
        fi
        
        # Create systemd service file
        echo "Setting up systemd service..."
        sudo bash -c "cat > /etc/systemd/system/${app_name}.service << EOF
[Unit]
Description=${app_name} service
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:8000 $app_module
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
        
        # Enable and start the service
        sudo systemctl enable "${app_name}.service"
        sudo systemctl start "${app_name}.service"
        
    else
        # For non-web applications, just set up a basic systemd service
        echo "Setting up basic Python application service..."
        sudo bash -c "cat > /etc/systemd/system/${app_name}.service << EOF
[Unit]
Description=${app_name} service
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/python $app_file
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
        
        # Enable and start the service
        sudo systemctl enable "${app_name}.service"
        sudo systemctl start "${app_name}.service"
    fi
    
    echo "Application deployed successfully!"
}

# Function to set up Java/Spring application
setup_java_spring() {
    echo "Setting up Java/Spring application..."
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Clone the repository
    git clone "$repo_url" .
    
    # Check for Maven or Gradle
    if [ -f "pom.xml" ]; then
        echo "Maven project detected..."
        # Build the project with Maven
        mvn clean package
        
        # Find the JAR file in target directory
        jar_file=$(find target -name "*.jar" | head -1)
    elif [ -f "build.gradle" ]; then
        echo "Gradle project detected..."
        # Build the project with Gradle
        ./gradlew build
        
        # Find the JAR file in build/libs directory
        jar_file=$(find build/libs -name "*.jar" | head -1)
    else
        echo "Neither Maven nor Gradle configuration found. Cannot build the project."
        exit 1
    fi
    
    # Create systemd service file
    echo "Setting up systemd service..."
    sudo bash -c "cat > /etc/systemd/system/${app_name}.service << EOF
[Unit]
Description=${app_name} service
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/java -jar $jar_file
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
    
    # Enable and start the service
    sudo systemctl enable "${app_name}.service"
    sudo systemctl start "${app_name}.service"
    
    echo "Application deployed successfully!"
}

# Function to set up Laravel application
setup_laravel() {
    echo "Setting up Laravel application..."
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Clone the repository
    git clone "$repo_url" .
    
    # Install Composer dependencies
    echo "Installing Composer dependencies..."
    composer install --no-dev --optimize-autoloader
    
    # Set up .env file
    if [ -f ".env.example" ]; then
        cp .env.example .env
        php artisan key:generate
        
        # Prompt for database configuration
        get_input "Enter database name" db_name
        get_input "Enter database user" db_user
        get_input "Enter database password" db_password
        
        # Update .env file with database credentials
        sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" .env
        sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" .env
        sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_password/" .env
    fi
    
    # Set proper permissions
    chmod -R 775 storage bootstrap/cache
    
    # Run migrations
    echo "Running database migrations..."
    php artisan migrate --force
    
    # Optimize Laravel
    php artisan optimize
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    
    # Set up Apache/Nginx configuration
    echo "Setting up web server configuration..."
    if command -v apache2 &> /dev/null; then
        # Apache configuration
        sudo bash -c "cat > /etc/apache2/sites-available/${app_name}.conf << EOF
<VirtualHost *:80>
    ServerName ${app_name}
    DocumentRoot $(pwd)/public
    
    <Directory $(pwd)/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/${app_name}_error.log
    CustomLog \${APACHE_LOG_DIR}/${app_name}_access.log combined
</VirtualHost>
EOF"
        
        sudo a2ensite ${app_name}
        sudo systemctl reload apache2
        
    elif command -v nginx &> /dev/null; then
        # Nginx configuration
        sudo bash -c "cat > /etc/nginx/sites-available/${app_name} << EOF
server {
    listen 80;
    server_name ${app_name};
    root $(pwd)/public;
    
    add_header X-Frame-Options 'SAMEORIGIN';
    add_header X-XSS-Protection '1; mode=block';
    add_header X-Content-Type-Options 'nosniff';
    
    index index.php;
    charset utf-8;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    
    error_page 404 /index.php;
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF"
        
        sudo ln -s /etc/nginx/sites-available/${app_name} /etc/nginx/sites-enabled/
        sudo systemctl reload nginx
    else
        echo "Neither Apache nor Nginx found. Please install a web server manually."
    fi
    
    echo "Laravel application deployed successfully!"
}

# Function to set up Remix application
setup_remix() {
    echo "Setting up Remix application..."
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Clone the repository
    git clone "$repo_url" .
    
    # Install dependencies
    echo "Installing dependencies..."
    npm install
    
    # Build the application
    echo "Building Remix application..."
    npm run build
    
    # Get port number for the application
    get_input "Enter the port number for the Remix app (e.g., 3000)" app_port
    get_input "Enter the domain name (e.g., example.com)" domain_name
    
    # Create systemd service file for the Remix app
    echo "Setting up systemd service..."
    sudo bash -c "cat > /etc/systemd/system/${app_name}.service << EOF
[Unit]
Description=${app_name} Remix service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
Environment=PORT=${app_port}
Environment=NODE_ENV=production
ExecStart=$(which npm) start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"
    
    # Set up Nginx configuration as reverse proxy
    echo "Setting up Nginx configuration..."
    sudo bash -c "cat > /etc/nginx/sites-available/${app_name} << EOF
# Upstream for Remix app
upstream ${app_name}_upstream {
    server 127.0.0.1:${app_port};
    keepalive 64;
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name ${domain_name};
    return 301 https://\$server_name\$request_uri;
}

# Main server block
server {
    listen 443 ssl http2;
    server_name ${domain_name};

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/${domain_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain_name}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    # SSL Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Logs
    access_log /var/log/nginx/${app_name}_access.log combined buffer=512k flush=1m;
    error_log /var/log/nginx/${app_name}_error.log warn;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:${app_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Cache static files
    location /_assets {
        alias $(pwd)/public/build;
        expires 30d;
        access_log off;
        add_header Cache-Control "public, no-transform";
    }

    # Enable Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/javascript application/xml;
    gzip_disable "MSIE [1-6]\.";
}
EOF"
    
    # Create symbolic link and test Nginx configuration
    sudo ln -sf /etc/nginx/sites-available/${app_name} /etc/nginx/sites-enabled/
    sudo nginx -t
    
    # If Nginx test is successful, reload Nginx
    if [ $? -eq 0 ]; then
        sudo systemctl reload nginx
        echo "Nginx configuration has been updated successfully!"
    else
        echo "Error in Nginx configuration. Please check the syntax."
        exit 1
    fi
    
    # Set up SSL certificate using Certbot (if not already installed)
    if ! command -v certbot &> /dev/null; then
        echo "Installing Certbot..."
        sudo apt update
        sudo apt install -y certbot python3-certbot-nginx
    fi
    
    # Obtain SSL certificate
    echo "Obtaining SSL certificate..."
    sudo certbot --nginx -d ${domain_name} --non-interactive --agree-tos --email $(whoami)@${domain_name} --redirect
    
    # Enable and start the service
    sudo systemctl enable "${app_name}.service"
    sudo systemctl start "${app_name}.service"
    
    echo "Remix application deployed successfully!"
    echo "Your application is now accessible at https://${domain_name}"
}

# Main script
display_header

# Get the repository URL
get_input "Enter the git repository URL" repo_url validate_repo_url

# Get application name
get_input "Enter the application name (for service naming)" app_name

# Get deployment directory
get_input "Enter the deployment directory path" deploy_dir

# Get technology type
PS3="Select the technology type: "
technologies=("Node.js" "Python" "Java/Spring" "Laravel" "Remix" "Quit")
select tech in "${technologies[@]}"; do
    case $tech in
        "Node.js")
            setup_nodejs
            break
            ;;
        "Python")
            setup_python
            break
            ;;
        "Java/Spring")
            setup_java_spring
            break
            ;;
        "Laravel")
            setup_laravel
            break
            ;;
        "Remix")
            setup_remix
            break
            ;;
        "Quit")
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done

echo "Deployment completed. Check service status with: sudo systemctl status $app_name"