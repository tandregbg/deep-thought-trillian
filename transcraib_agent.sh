#!/bin/bash

# Script: transcraib_agent.sh
# Description: Install, uninstall, or monitor directories for various file types and copy them to a destination directory.

# Constants
PLIST_PATH="$HOME/Library/LaunchAgents/com.transcraib.transcraib_agent.plist"
SCRIPT_PATH="$HOME/transcraib_agent.sh"
CONFIG_PATH="$HOME/.transcraib_config"
LOG_FILE="$HOME/transcraib_agent.log"
APP_PATH="/Applications/TranscraibAgent.app"

# Log initialization
log_action() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

# Handle Ctrl+C gracefully
trap_ctrlc() {
    echo -e "\nOperation cancelled by user"
    exit 1
}

trap trap_ctrlc INT

# Directory handling functions
list_directory_contents() {
    local dir="$1"
    local pattern="$2"
    local count=10

    echo "Contents (last $count items):"
    
    # Use find for better handling of spaces and special characters
    if [ -z "$pattern" ]; then
        # List directories first
        find "$dir" -maxdepth 1 -type d ! -path "$dir" -print0 2>/dev/null | 
        while IFS= read -r -d '' item; do
            echo "  [DIR] $(basename "$item")"
        done | head -n "$count"
        
        # Then list files
        find "$dir" -maxdepth 1 -type f -print0 2>/dev/null |
        while IFS= read -r -d '' item; do
            echo "  $(basename "$item")"
        done | head -n "$count"
    else
        find "$dir" -maxdepth 1 -type f -name "*$pattern" -print0 2>/dev/null |
        while IFS= read -r -d '' item; do
            echo "  $(basename "$item")"
        done | head -n "$count"
    fi
    
    # Get total count
    local total_count=0
    if [ -z "$pattern" ]; then
        total_count=$(find "$dir" -maxdepth 1 ! -path "$dir" 2>/dev/null | wc -l)
    else
        total_count=$(find "$dir" -maxdepth 1 -type f -name "*$pattern" 2>/dev/null | wc -l)
    fi
    
    if [ "$total_count" -gt "$count" ]; then
        echo "  ... and $(($total_count - $count)) more items"
    fi
    echo
}

validate_directory() {
    local dir="$1"
    if [ -d "$dir" ]; then
        return 0
    fi
    return 1
}

confirm_action() {
    local prompt="$1"
    local result
    
    echo -n "$prompt (y/n): "
    read -r -n 1 result
    echo
    
    [[ "$result" = "y" ]] || [[ "$result" = "Y" ]]
}

create_monitor_app() {
    echo "Creating monitor application..."
    
    # Create app bundle structure
    mkdir -p "$APP_PATH/Contents/MacOS"
    
    # Create Info.plist
    cat > "$APP_PATH/Contents/Info.plist" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TranscraibAgent</string>
    <key>CFBundleIdentifier</key>
    <string>com.transcraib.agent</string>
    <key>CFBundleName</key>
    <string>TranscraibAgent</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.10</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
EOL
    
    # Create executable script
    cat > "$APP_PATH/Contents/MacOS/TranscraibAgent" <<EOL
#!/bin/bash
exec "$SCRIPT_PATH" --monitor
EOL
    
    # Make executable
    chmod +x "$APP_PATH/Contents/MacOS/TranscraibAgent"
    
    echo "✓ Created monitor application at: $APP_PATH"
    echo "Please grant Full Disk Access permission to the app in:"
    echo "System Settings > Privacy & Security > Full Disk Access"
    echo "Then select $APP_PATH"
}

install_transcraib() {
    log_action "Starting installation of Transcraib agent."
    
    # Create monitor app if it doesn't exist
    if [[ ! -d "$APP_PATH" ]]; then
        create_monitor_app
    fi
    
    # First, check if we need to install the script
    if [[ "$(realpath "$0")" != "$(realpath "$SCRIPT_PATH")" ]]; then
        echo "=== Installing Transcraib Agent ==="
        echo "Step 1: Copying script to home directory..."
        mkdir -p "$(dirname "$SCRIPT_PATH")"
        cp "$0" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        echo "✓ Script installed to: $SCRIPT_PATH"
        echo -e "\nWhat happens next:"
        echo "1. Run the script again from its new location"
        echo "2. This will set up the background service"
        echo -e "\nRun this command:"
        echo "bash $SCRIPT_PATH --install"
        exit 0
    fi
    
    # Check if configuration exists
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "=== Configuration Missing ==="
        echo "The configuration file was not found."
        echo -e "\nTo set up Transcraib:"
        echo "1. First run: transcraib_config.sh"
        echo "2. Then run: transcraib_agent.sh --install"
        exit 1
    fi
    
    echo "Reading configuration..."

    # Create LaunchAgent plist
    cat > "$PLIST_PATH" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.transcraib.transcraib_agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_PATH/Contents/MacOS/TranscraibAgent</string>
        <string>--background</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
EOL

    echo -e "\n=== Installing Transcraib Agent ===\n"
    echo "Creating LaunchAgent configuration..."
    if launchctl unload "$PLIST_PATH" 2>/dev/null; then
        echo "✓ Unloaded existing agent"
    fi
    if launchctl load "$PLIST_PATH"; then
        echo "✓ Loaded new agent configuration"
        log_action "Transcraib agent installed and launched."
        echo -e "\n✓ Installation Complete! Agent is now active.\n"
    else
        echo "✗ Failed to load agent"
        log_action "Failed to load Transcraib agent."
        echo -e "\n✗ Installation failed. Please check the logs.\n"
    fi
    
    echo -e "=== Current Configuration ===\n"
    check_status
}

uninstall_transcraib() {
    if confirm_action "Are you sure you want to uninstall Transcraib agent?"; then
        log_action "Uninstalling Transcraib agent."
        
        # Stop and remove LaunchAgent
        launchctl unload "$PLIST_PATH" 2>/dev/null
        rm -f "$PLIST_PATH"
        
        # Remove the app bundle
        if [[ -d "$APP_PATH" ]]; then
            rm -rf "$APP_PATH"
            echo "✓ Removed TranscraibAgent.app"
        fi
        
        log_action "Transcraib agent uninstalled."
        echo "✓ Transcraib agent uninstalled (scripts and configuration preserved)"
        
        echo -e "\nNote: You may want to manually remove Full Disk Access permission for"
        echo "TranscraibAgent from System Settings > Privacy & Security > Full Disk Access"
        
        echo -e "\nTo reinstall the agent later:"
        echo "1. Run: transcraib_agent.sh --install"
    else
        echo "Uninstall cancelled."
    fi
}

check_status() {
    log_action "Checking Transcraib agent status."
    
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "Status: Not Configured"
        return
    fi

    if launchctl list | grep -q "com.transcraib.transcraib_agent"; then
        echo "Status: Installed and Running (Background Service)"
        echo -e "\nCurrent Configuration:"
        
        local dest_dir=""
        while IFS='=' read -r key value; do
            if [[ "$key" == "DEST_DIR" ]]; then
                dest_dir="$value"
                if [[ -n "$dest_dir" ]] && validate_directory "$dest_dir"; then
                    echo -e "\nDestination Directory: $dest_dir"
                    list_directory_contents "$dest_dir"
                else
                    echo -e "\nDestination Directory: $dest_dir (not accessible)"
                fi
            elif [[ "$key" == "SOURCE" ]]; then
                local dir="${value%%:*}"
                local tag="${value#*:}"; tag="${tag%%:*}"
                local ext="${value##*:}"
                if validate_directory "$dir"; then
                    local count=$(find "$dir" -maxdepth 1 -type f -name "*$ext" | wc -l)
                    echo "- [$tag] $dir ($ext) - $count matching files"
                else
                    echo "- [$tag] $dir ($ext) - directory not accessible"
                fi
            fi
        done < "$CONFIG_PATH"
        
        log_action "Transcraib agent is running."
        echo -e "\nLast 5 log entries:"
        tail -n 5 "$LOG_FILE"
    else
        echo "Status: Not Running (but configured)"
        log_action "Transcraib agent is not running."
    fi
}

monitor_directories() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_action "No configuration found. Please run --install first."
        exit 1
    fi

    local dest_dir=""
    local -a monitor_dirs=()
    local processed_files_db="/tmp/transcraib_processed_$$.txt"
    touch "$processed_files_db"
    
    # Cleanup on exit
    trap 'rm -f "$processed_files_db"' EXIT

    # Read configuration
    while IFS='=' read -r key value; do
        if [[ "$key" == "DEST_DIR" ]]; then
            dest_dir="$value"
        elif [[ "$key" == "SOURCE" ]]; then
            monitor_dirs+=("$value")
        fi
    done < "$CONFIG_PATH"

    # When running in background via LaunchAgent, redirect output to log file
    if [[ "${1:-}" == "--background" ]]; then
        exec 1>> "$LOG_FILE" 2>&1
        log_action "Starting background monitoring with destination: $dest_dir"
    else
        log_action "Starting monitoring with destination: $dest_dir"
        echo -e "\n=== Current Configuration ===\n"
        echo "Status: Running in foreground (--monitor mode)"
        echo -e "\nDestination Directory: $dest_dir"
        if validate_directory "$dest_dir"; then
            list_directory_contents "$dest_dir"
        else
            echo "Warning: Destination directory not accessible"
        fi
        
        echo -e "\nMonitored Source Directories:"
        for source in "${monitor_dirs[@]}"; do
            local dir="${source%%:*}"
            local tag="${source#*:}"; tag="${tag%%:*}"
            local ext="${source##*:}"
            
            if validate_directory "$dir"; then
                local count=$(find "$dir" -type f -name "*$ext" 2>/dev/null | wc -l)
                echo "- [$tag] $dir ($ext) - $count matching files"
            else
                echo "- [$tag] $dir ($ext) - directory not accessible"
            fi
        done
    fi
    
    # Initialize processed_files_db with existing files
    for source in "${monitor_dirs[@]}"; do
        local dir="${source%%:*}"
        local tag="${source#*:}"; tag="${tag%%:*}"
        local ext="${source##*:}"
        
        if validate_directory "$dir"; then
            find "${dir}" -type f -name "*${ext}" 2>/dev/null | while IFS= read -r file; do
                mtime=$(stat -f "%m" "$file")
                echo "$file:$mtime" >> "$processed_files_db"
            done
        fi
    done
    
    if [[ "${1:-}" != "--background" ]]; then
        echo -e "\nInitialized with existing files. Monitoring for new files..."
    fi
    
    while true; do
        for source in "${monitor_dirs[@]}"; do
            local dir="${source%%:*}"
            local tag="${source#*:}"; tag="${tag%%:*}"
            local ext="${source##*:}"
            
            if ! validate_directory "$dir"; then
                continue
            fi

            find "$dir" -type f -name "*$ext" 2>/dev/null | while IFS= read -r file; do
                # Get current modification time
                current_mtime=$(stat -f "%m" "$file")
                
                # Check if file exists in db with same mtime
                if ! grep -q "^$file:" "$processed_files_db" || \
                   ! grep -q "^$file:$current_mtime$" "$processed_files_db"; then
                    # Either new file or modified file - update db
                    sed -i '' "/^$file:/d" "$processed_files_db" 2>/dev/null
                    echo "$file:$current_mtime" >> "$processed_files_db"
                    
                    # Create a more descriptive filename that includes the subdirectory path
                    local rel_path="${file#$dir/}"
                    local subdir_path="${rel_path%/*}"
                    if [[ "$rel_path" == "$subdir_path" ]]; then
                        # File is directly in the monitored directory
                        local dest_filename="[${tag}]_$(basename "$file")"
                    else
                        # File is in a subdirectory - replace slashes with underscores
                        local dest_filename="[${tag}]_${subdir_path//\//_}_$(basename "$file")"
                    fi
                    
                    # Add timestamp to filename for modified files
                    if grep -q "^$file:" "$processed_files_db"; then
                        # File was modified - add timestamp
                        local timestamp=$(date +"%Y%m%d_%H%M%S")
                        dest_filename="${dest_filename%.*}_${timestamp}.${dest_filename##*.}"
                    fi
                    
                    if cp "$file" "$dest_dir/$dest_filename"; then
                        if grep -q "^$file:" "$processed_files_db"; then
                            log_action "Updated [$tag] $rel_path to $dest_dir/$dest_filename"
                        else
                            log_action "Copied [$tag] $rel_path to $dest_dir/$dest_filename"
                        fi
                    else
                        log_action "Error copying [$tag] $rel_path"
                    fi
                fi
            done
        done
        sleep 5
    done
}

    # Main execution
case "$1" in
    --create-app)
        create_monitor_app
        ;;
    --install|--reinstall)
        # Check if we're running from the correct location
        if [[ "$(realpath "$0")" != "$(realpath "$SCRIPT_PATH")" ]]; then
            # Create parent directory if needed
            mkdir -p "$(dirname "$SCRIPT_PATH")"
            
            # Copy script to home directory
            cp "$0" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            
            # Run the script from the new location
            echo "✓ Script installed to $SCRIPT_PATH"
            echo "Please run the script again from the new location:"
            echo "bash $SCRIPT_PATH --install"
            exit 0
        fi
        
        # Now running from correct location
        if [[ "$1" == "--reinstall" ]]; then
            echo "Uninstalling existing configuration..."
            uninstall_transcraib
            echo -e "\nInstalling new configuration..."
        fi
        install_transcraib
        ;;
    --uninstall)
        uninstall_transcraib
        ;;
    --monitor)
        monitor_directories "${2:-}"
        ;;
    *)
        check_status
        echo -e "\nTranscraib Agent Commands"
        echo "======================="
        echo "This tool monitors directories and automatically copies new files."
        echo -e "\nAvailable commands:"
        echo "  --install    Set up and start the background monitoring service"
        echo "               Use this after running transcraib_config.sh"
        echo
        echo "  --reinstall  Remove existing setup and install fresh"
        echo "               Use this if you want to start over"
        echo
        echo "  --uninstall  Stop and remove the monitoring service"
        echo "               Use this to completely remove Transcraib"
        echo
        echo "  --monitor    Run in foreground mode for testing"
        echo "               Shows real-time file copying activity"
        echo
        echo "  --create-app Create the monitor application"
        echo "               Required for full disk access"
        echo
        echo "  (no args)    Show current status and configuration"
        echo "               See what directories are being monitored"
        echo -e "\nExample usage:"
        echo "  bash $0 --install    # Start monitoring"
        echo "  bash $0              # Check status"
        ;;
esac
