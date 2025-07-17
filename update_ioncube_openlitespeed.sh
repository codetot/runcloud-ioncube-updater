#!/bin/bash

# This script automates the installation of ionCube Loader for multiple PHP versions
# (7.4, 8.0, 8.1, 8.2, 8.3, 8.4) on OpenLiteSpeed web server.

# Define the PHP versions to install ionCube Loader for.
# These versions correspond to the 'lsphp' binaries used by OpenLiteSpeed.
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3" "8.4")

# URL to download the ionCube Loader package for Linux x86-64.
# This URL is typically stable, but can be updated if ionCube changes its download structure.
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
# wget is used for downloading, tar for extraction, and systemctl for service control.
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

    # Construct the expected path for the OpenLiteSpeed PHP binary.
    # OpenLiteSpeed typically installs PHP binaries in /usr/local/lsws/lsphpX.Y/bin/php.
    # The version number is converted (e.g., "7.4" becomes "74").
    LS_PHP_BIN="/usr/local/lsws/lsphp${PHP_VERSION//./}/bin/php"

    # Check if the OpenLiteSpeed PHP binary exists for the current version.
    if [ ! -f "$LS_PHP_BIN" ]; then
        log_message "OpenLiteSpeed PHP $PHP_VERSION binary not found at $LS_PHP_BIN. Skipping this version."
        continue # Move to the next PHP version in the loop.
    fi

    # Find the php.ini configuration file path for the current PHP version.
    # We execute the specific lsphp binary to get its configuration details.
    PHP_INI_PATH=$("$LS_PHP_BIN" -i 2>/dev/null | grep "Loaded Configuration File" | awk '{print $NF}')
    if [ -z "$PHP_INI_PATH" ]; then
        log_message "Could not find php.ini for PHP $PHP_VERSION using $LS_PHP_BIN. Skipping."
        continue
    fi
    log_message "Found php.ini for PHP $PHP_VERSION at: $PHP_INI_PATH"

    # Find the extension_dir for the current PHP version.
    # This is where PHP looks for its extensions.
    EXTENSION_DIR=$("$LS_PHP_BIN" -i 2>/dev/null | grep "extension_dir =>" | awk '{print $NF}' | head -n 1)
    if [ -z "$EXTENSION_DIR" ]; then
        log_message "Could not find extension_dir for PHP $PHP_VERSION using $LS_PHP_BIN. Skipping."
        continue
    fi
    log_message "Found extension_dir for PHP $PHP_VERSION at: $EXTENSION_DIR"

    # Determine the specific ionCube loader file name for the current PHP version.
    # The extracted ionCube package contains loaders named like 'ioncube_loader_lin_X.Y.so'.
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
        # Add the zend_extension line to the php.ini file.
        # Using 'tee -a' ensures the line is appended and also printed to stdout (for logging).
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

# Restart OpenLiteSpeed service to apply the new PHP configurations.
log_message "Restarting OpenLiteSpeed service (lsws-rc)..."
# Use lsws-rc service name as per user's guideline.
systemctl restart lsws-rc || error_message "Failed to restart OpenLiteSpeed service (lsws-rc). Please restart it manually using 'sudo systemctl restart lsws-rc' if necessary."

# Kill all lsphp processes to ensure new configurations are loaded.
log_message "Killing all lsphp processes to ensure new configurations are loaded..."
killall lsphp 2>/dev/null || log_message "No lsphp processes found to kill, or failed to kill them. This might be normal if they already restarted."

log_message "ionCube Loader installation process complete for all specified PHP versions."
log_message "Please verify the installation by creating a phpinfo() file for each PHP version and checking for 'ionCube Loader' in the output."
log_message "Example: Create a file named info.php with content <?php phpinfo(); ?> in your web root."
