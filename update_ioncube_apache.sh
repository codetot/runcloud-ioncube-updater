#!/bin/bash

# This script automates the installation of ionCube Loader for multiple PHP versions
# (7.4, 8.0, 8.1, 8.2, 8.3, 8.4) on Apache web server.

# Define the PHP versions to install ionCube Loader for.
# These versions correspond to common PHP installations on Apache.
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3" "8.4")

# URL to download the ionCube Loader package for Linux x86-64.
IONCUBE_DOWNLOAD_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"

# Temporary directory for downloading and extracting ionCube files.
TMP_DIR="/tmp/ioncube_install"

# --- Functions ---

# Function to log informational messages to the console.
log_message() {
    echo "[INFO] $1"
}

# Function to log error messages and exit the script.
error_message() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-installation Checks ---

# Check if the script is being run as root.
# ionCube installation and system service restarts require root privileges.
if [[ $EUID -ne 0 ]]; then
   error_message "This script must be run as root. Please run with 'sudo bash script_name.sh'."
fi

# Check for necessary commands.
# wget for downloading, tar for extraction, and systemctl for service control.
for cmd in wget tar systemctl; do
    if ! command -v "$cmd" &> /dev/null; then
        error_message "$cmd is not installed. Please install it before running this script (e.g., 'sudo apt install $cmd' or 'sudo yum install $cmd')."
    fi
done

# --- Main Installation Process ---

# Create and navigate to the temporary directory.
log_message "Creating temporary directory: $TMP_DIR"
mkdir -p "$TMP_DIR" || error_message "Failed to create temporary directory '$TMP_DIR'."
cd "$TMP_DIR" || error_message "Failed to change to temporary directory '$TMP_DIR'."

# Download ionCube Loader package.
log_message "Downloading ionCube Loader from $IONCUBE_DOWNLOAD_URL..."
wget -q --show-progress "$IONCUBE_DOWNLOAD_URL" -O ioncube_loaders_lin_x86-64.tar.gz || error_message "Failed to download ionCube Loader. Check your internet connection or the URL."

# Extract ionCube Loader files.
log_message "Extracting ionCube Loader..."
tar -xzf ioncube_loaders_lin_x86-64.tar.gz || error_message "Failed to extract ionCube Loader. The downloaded file might be corrupt or incomplete."

# Loop through each specified PHP version.
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    log_message "--- Processing PHP $PHP_VERSION ---"

    # Attempt to find the php.ini path for the Apache SAPI.
    # Common paths include /etc/php/X.Y/apache2/php.ini or /etc/php/X.Y/fpm/php.ini
    # We prioritize the 'apache2' SAPI if it exists.
    PHP_INI_PATH=""
    if [ -f "/etc/php/${PHP_VERSION}/apache2/php.ini" ]; then
        PHP_INI_PATH="/etc/php/${PHP_VERSION}/apache2/php.ini"
    elif [ -f "/etc/php/${PHP_VERSION}/fpm/php.ini" ]; then
        # Fallback to FPM php.ini if apache2 SAPI is not found,
        # as some Apache setups might use PHP-FPM.
        PHP_INI_PATH="/etc/php/${PHP_VERSION}/fpm/php.ini"
    else
        # Try to find it dynamically via the php-cli if direct path not found.
        # This might point to CLI php.ini, but we'll try to use it if nothing else is found.
        PHP_CLI_BIN="/usr/bin/php${PHP_VERSION}"
        if [ -f "$PHP_CLI_BIN" ]; then
            PHP_INI_PATH=$("$PHP_CLI_BIN" -i 2>/dev/null | grep "Loaded Configuration File" | awk '{print $NF}')
        fi
    fi

    if [ -z "$PHP_INI_PATH" ] || [ ! -f "$PHP_INI_PATH" ]; then
        log_message "Could not find a suitable php.ini for PHP $PHP_VERSION. Skipping this version."
        continue
    fi
    log_message "Found php.ini for PHP $PHP_VERSION at: $PHP_INI_PATH"

    # Find the extension_dir for the current PHP version.
    # We use the PHP CLI binary to determine this, as it typically reflects the extension path.
    EXTENSION_DIR=$("/usr/bin/php${PHP_VERSION}" -i 2>/dev/null | grep "extension_dir =>" | awk '{print $NF}' | head -n 1)
    if [ -z "$EXTENSION_DIR" ]; then
        log_message "Could not find extension_dir for PHP $PHP_VERSION. Skipping."
        continue
    fi
    log_message "Found extension_dir for PHP $PHP_VERSION at: $EXTENSION_DIR"

    # Determine the specific ionCube loader file name for the current PHP version.
    IONCUBE_LOADER_FILE="ioncube_loader_lin_${PHP_VERSION}.so"
    IONCUBE_SOURCE_PATH="${TMP_DIR}/ioncube/${IONCUBE_LOADER_FILE}"

    # Check if the specific ionCube loader file exists in the extracted directory.
    if [ ! -f "$IONCUBE_SOURCE_PATH" ]; then
        log_message "ionCube loader file for PHP $PHP_VERSION not found at $IONCUBE_SOURCE_PATH. Skipping this version."
        continue
    fi

    # Copy the ionCube loader file to the PHP extension directory.
    log_message "Copying $IONCUBE_LOADER_FILE to $EXTENSION_DIR..."
    cp "$IONCUBE_SOURCE_PATH" "$EXTENSION_DIR/" || error_message "Failed to copy ionCube loader for PHP $PHP_VERSION to $EXTENSION_DIR."

    # Configure php.ini to load the ionCube extension.
    log_message "Configuring php.ini for PHP $PHP_VERSION..."
    # Check if the zend_extension line already exists to prevent duplication.
    if ! grep -q "zend_extension=\"${EXTENSION_DIR}/${IONCUBE_LOADER_FILE}\"" "$PHP_INI_PATH"; then
        echo "zend_extension=\"${EXTENSION_DIR}/${IONCUBE_LOADER_FILE}\"" | tee -a "$PHP_INI_PATH" > /dev/null
        log_message "Added zend_extension line to $PHP_INI_PATH."
    else
        log_message "zend_extension line already exists in $PHP_INI_PATH. Skipping configuration for this version."
    fi

done

# --- Post-installation Steps ---

# Clean up the temporary directory.
log_message "Cleaning up temporary directory: $TMP_DIR"
rm -rf "$TMP_DIR"

# Restart Apache service to apply the new PHP configurations.
log_message "Restarting Apache service..."
# Check for common Apache service names and restart the active one.
if systemctl is-active --quiet apache2; then
    systemctl restart apache2 || error_message "Failed to restart Apache service (apache2). Please restart it manually."
elif systemctl is-active --quiet httpd; then
    systemctl restart httpd || error_message "Failed to restart Apache service (httpd). Please restart it manually."
else
    error_message "Could not find active Apache service (apache2 or httpd). Please restart your Apache service manually."
fi

log_message "ionCube Loader installation process complete for all specified PHP versions."
log_message "Please verify the installation by creating a phpinfo() file for each PHP version and checking for 'ionCube Loader' in the output."
log_message "Example: Create a file named info.php with content <?php phpinfo(); ?> in your web root."
