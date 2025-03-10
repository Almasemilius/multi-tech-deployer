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
    
    # Detect PHP version
    php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    if [ -z "$php_version" ]; then
        echo "Error: Could not detect PHP version"
        exit 1
    fi
    echo "Detected PHP version: $php_version"
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Check if directory is not empty
    if [ "$(ls -A .)" ]; then
        echo "Directory is not empty."
        get_input "Do you want to remove existing files? (yes/no)" should_remove
        
        if [ "$should_remove" = "yes" ]; then
            echo "Removing existing files..."
            rm -rf ./*
            rm -rf ./.[!.]*  # Remove hidden files too
        else
            echo "Cannot proceed with non-empty directory. Please clear it manually or choose a different directory."
            exit 1
        fi
    fi
    
    # Ask for branch name (optional)
    get_input "Enter the branch name (press Enter for default branch)" branch_name
    
    # Clone the repository
    if [ -n "$branch_name" ]; then
        echo "Cloning repository from branch: $branch_name"
        git clone -b "$branch_name" "$repo_url" .
    else
        echo "Cloning repository from default branch"
        git clone "$repo_url" .
    fi
    
    # Install Composer dependencies
    echo "Installing Composer dependencies..."
    composer install --no-dev --optimize-autoloader
    
    # Set up .env file
    if [ -f ".env.example" ]; then
        cp .env.example .env
        php artisan key:generate
        
        # Prompt for database type
        PS3="Select the database type: "
        db_options=("MySQL" "PostgreSQL" "SQLite")
        select db_type in "${db_options[@]}"; do
            case $db_type in
                "MySQL")
                    db_connection="mysql"
                    break
                    ;;
                "PostgreSQL")
                    db_connection="pgsql"
                    break
                    ;;
                "SQLite")
                    db_connection="sqlite"
                    touch database/database.sqlite
                    break
                    ;;
                *)
                    echo "Invalid option. Please select a valid database type."
                    ;;
            esac
        done
        
        # If not SQLite, get additional database details
        if [ "$db_connection" != "sqlite" ]; then
            get_input "Enter database name" db_name
            get_input "Enter database user" db_user
            get_input "Enter database password" db_password
            get_input "Enter database host (default: localhost)" db_host
            db_host=${db_host:-localhost}
            get_input "Enter database port (default: 3306 for MySQL, 5432 for PostgreSQL)" db_port
            
            # Set default port if not provided
            if [ -z "$db_port" ]; then
                if [ "$db_connection" = "mysql" ]; then
                    db_port="3306"
                else
                    db_port="5432"
                fi
            fi
            
            # Simply remove the # from the beginning of each DB line
            sed -i 's/^# DB_HOST=/DB_HOST=/' .env
            sed -i 's/^# DB_PORT=/DB_PORT=/' .env
            sed -i 's/^# DB_DATABASE=/DB_DATABASE=/' .env
            sed -i 's/^# DB_USERNAME=/DB_USERNAME=/' .env
            sed -i 's/^# DB_PASSWORD=/DB_PASSWORD=/' .env
            
            # Update the values
            sed -i "s/^DB_CONNECTION=.*$/DB_CONNECTION=${db_connection}/" .env
            sed -i "s/^DB_HOST=.*$/DB_HOST=${db_host}/" .env
            sed -i "s/^DB_PORT=.*$/DB_PORT=${db_port}/" .env
            sed -i "s/^DB_DATABASE=.*$/DB_DATABASE=${db_name}/" .env
            sed -i "s/^DB_USERNAME=.*$/DB_USERNAME=${db_user}/" .env
            sed -i "s/^DB_PASSWORD=.*$/DB_PASSWORD=${db_password}/" .env
        fi
    fi
    
    # Set proper permissions
    chmod -R 775 storage bootstrap/cache
    
    # Run migrations
    echo "Running database migrations..."
    php artisan migrate --force

	#Creating Storage Link
	echo "Creating Storage Link..."
	php artisan storage:link

	#Seed Database
	echo "Seeding database..."
	php artisan db:seed
    
    # Optimize Laravel
    php artisan optimize
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    
    # Get application name if not already set
    if [ -z "$app_name" ]; then
        get_input "Enter the application name (for service naming)" app_name
    fi

    # Get domain name if not already set
    if [ -z "$domain_name" ]; then
        get_input "Enter the domain name (e.g., example.com)" domain_name
    fi

    # Set up Nginx configuration
    echo "Setting up Nginx configuration..."
    sudo bash -c "cat > /etc/nginx/sites-available/${app_name}.conf << EOF
server {
    listen 80;
    server_name ${domain_name};
    
    root ${deploy_dir}/public;
    index index.php;
    
    location / {
        try_files \\\$uri \\\$uri/ /index.php?\\\$query_string;
    }
    
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \\\$document_root\\\$fastcgi_script_name;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF"
    
    sudo ln -sf /etc/nginx/sites-available/${app_name}.conf /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx

    echo "Laravel application deployed successfully!"
    echo "Your application is now accessible at http://${domain_name}"
}

# Function to set up Remix application
setup_remix() {
    echo "Setting up Remix application..."
    
    # Create deploy directory if it doesn't exist
    mkdir -p "$deploy_dir"
    cd "$deploy_dir"
    
    # Ask for branch name (optional)
    get_input "Enter the branch name (press Enter for default branch)" branch_name
    
    # Clone the repository
    if [ -n "$branch_name" ]; then
        echo "Cloning repository from branch: $branch_name"
        git clone -b "$branch_name" "$repo_url" .
    else
        echo "Cloning repository from default branch"
        git clone "$repo_url" .
    fi
    
    # Install dependencies
    echo "Installing dependencies..."
    npm install
    
    # Build the application
    echo "Building Remix application..."
    npm run build
    
    # Get domain name for the application
    get_input "Enter the domain name (e.g., example.com)" domain_name
    
    # Set up Nginx configuration
    echo "Setting up Nginx configuration..."
    sudo bash -c "cat > /etc/nginx/sites-available/${app_name} << 'EOF'
server {
    listen 80;
    server_name ${domain_name};

    # Static files
    location /_static {
        alias $(pwd)/public/build;
        try_files \$uri =404;
    }

    # Everything else goes to Remix
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_read_timeout 240s;
    }
}
EOF"
    
    # Create symbolic link and test Nginx configuration
    sudo ln -sf /etc/nginx/sites-available/${app_name} /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    
    # Create systemd service file
    echo "Setting up systemd service..."
    sudo bash -c "cat > /etc/systemd/system/${app_name}.service << EOF
[Unit]
Description=${app_name} Remix service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
Environment=PORT=3000
Environment=NODE_ENV=production
ExecStart=$(which npm) start
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
    
    # Enable and start the service
    sudo systemctl enable "${app_name}.service"
    sudo systemctl start "${app_name}.service"
    
    echo "Remix application deployed successfully!"
    echo "Your application is now accessible at http://${domain_name}"
    echo "Check the service status with: sudo systemctl status ${app_name}"
    echo "View logs with: sudo journalctl -u ${app_name} -f"
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