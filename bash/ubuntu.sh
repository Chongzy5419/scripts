#!/bin/bash
echo ''
export TERM=xterm-256color
echo $TERM


# Color settings in subshell
color_red=$(tput setaf 1)  # Red
color_green=$(tput setaf 2)  # Green
color_yellow=$(tput setaf 3)  # Yellow
color_blue=$(tput setaf 4)  # Blue
color_magenta=$(tput setaf 5)  # Magenta
color_cyan=$(tput setaf 6)  # Cyan
color_grey=$(tput setaf 7)  # Grey
color_reset=$(tput sgr0)

#SIXTH PART CHECK FOR APT PACKAGE
echo -e "\n${color_magenta}6: Checking for versions of installed apt packages${color_reset}"

#    Check if Apache is installed and get its version
apache_version=$(apache2 -v 2>/dev/null | grep "Server version" | awk '{print $3}' | cut -d'/' -f2)
if [ -z "$apache_version" ]; then
    echo "Apache version: ${color_red}Apache is not installed or could not be detected.${color_reset}"
    exit 1
else
    echo "Apache version: $apache_version"
fi

#    Check if PHP is installed and get its version
php_version=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}')
if [ -z "$php_version" ]; then
    echo "PHP version:    ${color_red}PHP is not installed or could not be detected.${color_reset}"
    exit 1
else
    echo "PHP version:    $php_version"
fi

#    Check if MYSQL is installed and get its version
sql_version=$(mysql --version 2>/dev/null |  awk '{print $3}')
if [ -z "$sql_version" ]; then
    echo "$SQL version:    ${color_red}SQL is not installed or could not be detected.${color_reset}"
    exit 1
else
    echo "SQL version:    $sql_version"
fi


#SEVENTH PART CHECK FOR APACHE2 MODULE
echo -e "\n${color_magenta}7: Checking for installed apache modules${color_reset}"

#    Check if SSL module is enabled in Apache
ssl_module=$(apache2ctl -M 2>/dev/null | grep -i 'ssl_module')
if [ -z "$ssl_module" ]; then
    echo "SSL module:     ${color_red}SSL module is not enabled in Apache.${color_reset}"
else
    echo "SSL module:     ${color_green}Enabled${color_reset}"
fi

#  Check if PHP module is enabled in Apache
php_module=$(apache2ctl -M 2>/dev/null | grep -i 'php_module')
if [ -z "$php_module" ]; then
    echo "PHP module:     ${color_red}PHP module is not enabled in Apache.${color_reset}"
else
    echo "PHP module:     ${color_green}Enabled${color_reset}"
fi


#EIGHTH PART CHECK FOR APACHE CONTENT
echo -e "\n${color_magenta}8: Checking for content in the Apache module${color_reset}"

#  Function to check WordPress database configuration
check_wp_db_config() {
    local wp_config_file="$1"

    db_name=$(grep -oP "define\(\s*'DB_NAME'\s*,\s*'\K[^']+" "$wp_config_file")
    db_user=$(grep -oP "define\(\s*'DB_USER'\s*,\s*'\K[^']+" "$wp_config_file")
    db_password=$(grep -oP "define\(\s*'DB_PASSWORD'\s*,\s*'\K[^']+" "$wp_config_file")
    db_host=$(grep -oP "define\(\s*'DB_HOST'\s*,\s*'\K[^']+" "$wp_config_file")

    if [ -n "$db_name" ] && [ -n "$db_user" ] && [ -n "$db_password" ] && [ -n "$db_host" ]; then        
        echo "${color_blue}Database Name:    ${color_reset} $db_name"
        echo "${color_blue}Database User:    ${color_reset} $db_user"
        echo "${color_blue}Database Password:${color_reset} $db_password"
        echo "${color_blue}Database Host:    ${color_reset} $db_host"
    else
        echo "${color_red}WordPress database is not yet fully set up.${color_reset}"
    fi

    #Attempt to connect to the database
    mysql -h "$db_host" -u "$db_user" -p"$db_password" "$db_name" -e "exit" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "${color_green}Successfully connected to the database.${color_reset}"
    else
        echo "${color_red}Failed to connect to the database. Please check the database credentials.${color_reset}"
    fi
}

#  Function to check SSL certificate validity
check_ssl_cert_validity() {
    local cert_path="$1"

    #Extract issuer and subject using OpenSSL
    issuer=$(openssl x509 -in "$cert_path" -noout -issuer | sed 's/issuer= //' | awk '{print $3}')
    subject=$(openssl x509 -in "$cert_path" -noout -subject | sed 's/subject= //' | awk '{print $3}' )

    #Check if the issuer and subject are the same (indicating a self-signed certificate)
    if [ "$issuer" == "$subject" ]; then
        echo "                      ${color_yellow}This is a self-signed certificate.${color_reset}"
    else
        echo "                      ${color_cyan}This is not a self-signed certificate.${color_reset}"
    fi

    #Use the local CA bundle to verify the certificate
    if openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt "$cert_path" > /dev/null 2>&1; then
        echo "                      ${color_cyan}The certificate is trusted by the local machine.${color_reset}"
    else
        echo "                      ${color_red}The certificate is NOT trusted by the local machine.${color_reset}"
    fi
}

#  MAIN Function to extract VirtualHost information and check for WordPress installation
extract_vhost_info() {
    local vhost_file="$1"

    # Extract VirtualHost blocks
    awk '/<VirtualHost/,/<\/VirtualHost>/' "$vhost_file" | while read -r line; do
        # Extract VirtualHost information
        if echo "$line" | grep -qE '^[[:space:]]*<VirtualHost[[:space:]]+([^>]+)>'; then
            vhost=$(echo "$line" | grep -oP '(?<=<VirtualHost ).*?(?=>)')
            domain_name=$(echo "$vhost" | awk '{print $1}' | cut -d':' -f1)
            port=$(echo "$vhost" | awk '{print $1}' | cut -d':' -f2)
        fi

        # Extract ServerName
        if echo "$line" | grep -qE '^[[:space:]]*ServerName[[:space:]]+'; then
            domain_name=$(echo "$line" | awk '{print $2}')
        fi

        # Extract DocumentRoot and print the info
        if echo "$line" | grep -qE '^[[:space:]]*DocumentRoot[[:space:]]+'; then
            doc_root=$(echo "$line" | awk '{print $2}')
            echo -e "${color_grey}Processing file:$vhost_file${color_reset}"
            echo "---------------------------------------------------------------------------------------"     
            
            echo "${color_cyan}Domain Name:        ${color_reset}  ${domain_name}"
            echo "${color_cyan}Port:               ${color_reset}  ${port}"
            echo "${color_cyan}Document Root:      ${color_reset}  ${doc_root}"
            
            #Check SSL configuration and auto-redirect
            ssl_cert=$(grep -i "SSLCertificateFile" "$vhost_file" | awk '$2 ~ /^\// {print $2}')
            ssl_key=$(grep -i "SSLCertificateKeyFile" "$vhost_file" | awk '{print $2}')
            if [ -n "$ssl_cert" ] && [ -n "$ssl_key" ]; then
              echo "${color_cyan}SSL Certificate Path:${color_reset} $ssl_cert"
              echo "${color_cyan}SSL Key Path:        ${color_reset} $ssl_key"

              #Check the validity of the SSL certificate 
              check_ssl_cert_validity "$ssl_cert"
            else
              echo "${color_red}No SSL configuration found in ${vhost_file}.${color_reset}"
              #Check for SSL auto-redirect
              if grep -qi "RewriteRule .*https" "$vhost_file"; then
                echo "${color_cyan}SSL auto-redirect is enabled.${color_reset}"
              else
                echo "${color_red}SSL auto-redirect is not enabled.${color_reset}"
              fi
            fi
            
            # Check if the directory contains a WordPress installation
            echo ""
            if [ -d "$doc_root" ]; then
                if [ -d "$doc_root/wp-admin" ] && [ -d "$doc_root/wp-content" ] && [ -d "$doc_root/wp-includes" ]; then
                    if [ -f "$doc_root/wp-config.php" ]; then
                        echo "${color_green}WordPress is installed in ${doc_root}${color_reset}"
                        check_wp_db_config "$doc_root/wp-config.php"
                    else
                        echo "${color_red}WordPress is installed but not yet set up (missing wp-config.php).${color_reset}"
                    fi
                else
                    echo "${color_red}WordPress is NOT installed in ${doc_root}${color_reset}"
                fi
            else
                echo "${color_red}Directory does not exist or is inaccessible: ${doc_root}${color_reset}"
            fi

            echo ""           
        fi
    done
}

#    Directory where Apache enabled Virtual Host files are stored
vhost_dir="/etc/apache2/sites-enabled"

#    Loop through all enabled virtual host files
for vhost_file in "$vhost_dir"/*.conf; do
    extract_vhost_info "$vhost_file"
done

#NINTH PART CHECK FOR NTP installation
echo -e "\n${color_magenta}9: Checking for NTP Installation${color_reset}"

# Check if NTP is installed
if command -v ntpd >/dev/null 2>&1; then
    echo "${color_green}NTP is installed.${color_reset}"
else
    echo "${color_red}NTP is not installed.${color_reset}"
    exit 1
fi

# Check NTP service status
if systemctl is-active --quiet ntp; then
    echo "${color_green}NTP service is running.${color_reset}"
else
    echo "${color_red}NTP service is not running.${color_reset}"
fi

# Check NTP configuration
ntp_conf="/etc/ntp.conf"
if [ -f "$ntp_conf" ]; then
    echo "${color_yellow}NTP configuration file found at: ${color_reset}$ntp_conf"
    echo "${color_yellow}Configured NTP peers :${color_reset}"
    grep "^pool" /etc/ntp.conf | awk '{print $2}'
else
    echo "${color_red}NTP configuration file not found.${color_reset}"
fi

#TENTH PART CHECK FOR CRON JOB
echo -e "\n${color_magenta}10: Listing Cron Jobs for Users "

# Function to list cron jobs for a specific user
list_user_cron_jobs() {
    local user="$1"
    echo "${color_cyan}Cron jobs for user: $user${color_reset}"
    crontab -l -u "$user" 2>/dev/null | grep -v  '#'|| echo "${color_yellow}No cron jobs found for user: $user${color_reset}"
}

# List cron jobs for users with /bin/bash login shell
awk -F: '$7 == "/bin/bash" {print $1}' /etc/passwd | while read -r user; do
    list_user_cron_jobs "$user"
    echo ""
done

exit