#!/bin/bash

# Script: deep-thought-trillian.sh
# Description: Advanced file monitoring and organization system
# Version: 1.0.0
# Supports: macOS and Ubuntu/Linux with LaunchAgent/systemd and cron variants

set -euo pipefail

# Constants
readonly SCRIPT_NAME="deep-thought-trillian"
readonly VERSION="1.0.0"
readonly CONFIG_DIR="$HOME/.deep-thought-trillian"
readonly CONFIG_PATH="$CONFIG_DIR/config.json"
readonly ENV_PATH="$CONFIG_DIR/.env"
readonly LOG_FILE="$CONFIG_DIR/deep-thought-trillian.log"
readonly PID_FILE="$CONFIG_DIR/deep-thought-trillian.pid"
readonly PROCESSED_DB="$CONFIG_DIR/deep-thought-trillian-processed-files"
readonly CRON_WRAPPER="$CONFIG_DIR/cron-monitor.sh"
readonly CRON_LOG="$CONFIG_DIR/cron-monitor.log"
readonly SCREEN_PID="$CONFIG_DIR/screen-session.pid"
readonly CRON_STATUS="$CONFIG_DIR/cron-status"

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

readonly OS_TYPE=$(detect_os)

# OS-specific configurations
case "$OS_TYPE" in
    "macos")
        readonly STAT_CMD="stat -f %m"
        readonly WATCH_CMD="fswatch"
        readonly SERVICE_TYPE="launchd"
        readonly SERVICE_DIR="$HOME/Library/LaunchAgents"
        readonly SERVICE_FILE="com.deep-thought-trillian.plist"
        ;;
    "linux")
        readonly STAT_CMD="stat -c %Y"
        readonly WATCH_CMD="inotifywait"
        readonly SERVICE_TYPE="systemd"
        readonly SERVICE_DIR="$HOME/.config/systemd/user"
        readonly SERVICE_FILE="deep-thought-trillian.service"
        ;;
    *)
        readonly STAT_CMD="stat -c %Y"
        readonly WATCH_CMD=""
        readonly SERVICE_TYPE="none"
        readonly SERVICE_DIR=""
        readonly SERVICE_FILE=""
        ;;
esac

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="[$(date +"%Y-%m-%d %H:%M:%S")]"
    
    # Create log directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Write to log file
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    
    # Only print to console if running interactively (not as a service)
    # Check if we have a terminal and if parent is not launchd
    if [[ -t 1 ]] && [[ "$PPID" != "1" ]] && [[ "$(ps -p $PPID -o comm= 2>/dev/null)" != "launchd" ]]; then
        case "$level" in
            "ERROR") echo -e "${RED}$timestamp [$level] $message${NC}" >&2 ;;
            "WARN")  echo -e "${YELLOW}$timestamp [$level] $message${NC}" ;;
            "INFO")  echo -e "${GREEN}$timestamp [$level] $message${NC}" ;;
            "DEBUG") echo -e "${BLUE}$timestamp [$level] $message${NC}" ;;
            *) echo "$timestamp [$level] $message" ;;
        esac
    fi
}

# Cron logging function
cron_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="[$(date +"%Y-%m-%d %H:%M:%S")]"
    
    # Create log directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Write to cron log file
    echo "$timestamp [$level] $message" >> "$CRON_LOG"
}

# Load environment variables from .env file
load_env() {
    if [[ -f "$ENV_PATH" ]]; then
        log "INFO" "Loading environment variables from $ENV_PATH"
        # Source .env file while ignoring comments and empty lines
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Export valid environment variables
            if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                export "$line"
            fi
        done < "$ENV_PATH"
    fi
}

# Generate default .env file
generate_env() {
    mkdir -p "$CONFIG_DIR"
    
    cat > "$ENV_PATH" << 'EOF'
# Deep Thought Trillian Environment Configuration
# Override JSON configuration with environment variables

# Core functionality
# DTT_SOURCE_DIR=~/Downloads
# DTT_DEST_DIR=~/Documents/organized-files
# DTT_FILE_TAG=download
# DTT_EXTENSIONS=pdf,jpg,png,mp4

# Behavior settings
# DTT_LOG_LEVEL=INFO
# DTT_POLL_INTERVAL=5
# DTT_REAL_TIME=true

# Feature flags
# DTT_VOICE_MEMOS=true
# DTT_AUTO_CREATE_DIRS=true
EOF
    
    log "INFO" "Generated default .env file at $ENV_PATH"
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source)
                DTT_SOURCE_DIR="$2"
                shift 2
                ;;
            -d|--dest)
                DTT_DEST_DIR="$2"
                shift 2
                ;;
            -t|--tag)
                DTT_FILE_TAG="$2"
                shift 2
                ;;
            -e|--extensions)
                DTT_EXTENSIONS="$2"
                shift 2
                ;;
            -l|--log-level)
                DTT_LOG_LEVEL="$2"
                shift 2
                ;;
            -p|--poll)
                DTT_POLL_INTERVAL="$2"
                shift 2
                ;;
            --setup)
                SETUP_ONLY=true
                shift
                ;;
            *)
                # Unknown option, skip
                shift
                ;;
        esac
    done
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if screen session exists
screen_session_exists() {
    screen -list 2>/dev/null | grep -q "deep-thought-trillian"
}

# Get screen session PID
get_screen_session_pid() {
    screen -list 2>/dev/null | grep "deep-thought-trillian" | cut -d. -f1 | tr -d '\t' 2>/dev/null || echo ""
}

# Check and install dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for jq (JSON processor)
    if ! command_exists jq; then
        missing_deps+=("jq")
    fi
    
    # Check for screen (required for cron mode)
    if ! command_exists screen; then
        missing_deps+=("screen")
    fi
    
    # Check for OS-specific file watcher
    case "$OS_TYPE" in
        "macos")
            if ! command_exists fswatch; then
                missing_deps+=("fswatch")
            fi
            ;;
        "linux")
            if ! command_exists inotifywait; then
                missing_deps+=("inotify-tools")
            fi
            ;;
    esac
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "WARN" "Missing dependencies: ${missing_deps[*]}"
        log "INFO" "Installing dependencies..."
        
        case "$OS_TYPE" in
            "macos")
                if command_exists brew; then
                    for dep in "${missing_deps[@]}"; do
                        if [[ "$dep" == "screen" ]]; then
                            # screen is usually pre-installed on macOS
                            if ! command_exists screen; then
                                brew install screen
                            fi
                        else
                            brew install "$dep"
                        fi
                    done
                else
                    log "ERROR" "Homebrew not found. Please install: ${missing_deps[*]}"
                    exit 1
                fi
                ;;
            "linux")
                if command_exists apt-get; then
                    sudo apt-get update
                    for dep in "${missing_deps[@]}"; do
                        sudo apt-get install -y "$dep"
                    done
                elif command_exists yum; then
                    for dep in "${missing_deps[@]}"; do
                        sudo yum install -y "$dep"
                    done
                else
                    log "ERROR" "Package manager not found. Please install: ${missing_deps[*]}"
                    exit 1
                fi
                ;;
        esac
    fi
}

# Generate default configuration
generate_config() {
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_PATH" << 'EOF'
{
  "destination": "~/Dropbox/organized-files",
  "watch_directories": [
    {
      "name": "voice_memos",
      "path": "~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
      "extensions": ["m4a", "wav"],
      "tag": "voice",
      "enabled": false
    },
    {
      "name": "turboscan_pdfs",
      "path": "~/Library/Mobile Documents/iCloud~com~novosoft~TurboScan/Documents",
      "extensions": ["pdf"],
      "tag": "scan",
      "enabled": false
    },
    {
      "name": "downloads",
      "path": "~/Downloads",
      "extensions": ["pdf", "jpg", "png", "mp4", "mov", "doc", "docx"],
      "tag": "download",
      "enabled": true
    },
    {
      "name": "desktop",
      "path": "~/Desktop",
      "extensions": ["pdf", "jpg", "png"],
      "tag": "desktop",
      "enabled": true
    },
    {
      "name": "documents",
      "path": "~/Documents",
      "extensions": ["pdf", "doc", "docx"],
      "tag": "documents",
      "enabled": false
    }
  ]
}
EOF
    
    log "INFO" "Generated default configuration at $CONFIG_PATH"
}

# Interactive configuration wizard
configure_interactive() {
    log "INFO" "Starting interactive configuration..."
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    echo
    echo "==================================="
    echo "   Deep Thought Trillian Configuration"
    echo "=================================="
    echo
    
    # Get destination directory
    local dest_dir=""
    while true; do
        echo "Step 1: Destination Directory"
        echo "-----------------------------"
        echo "Where should organized files be copied to?"
        echo
        printf "Enter destination path [~/Dropbox/organized-files]: "
        read -r input
        
        dest_dir="${input:-~/Dropbox/organized-files}"
        dest_dir="${dest_dir/#\~/$HOME}"  # Expand ~
        
        if [[ ! -d "$dest_dir" ]]; then
            echo "Directory doesn't exist. Create it? (y/n)"
            read -r -n 1 create
            echo
            if [[ "$create" =~ ^[Yy]$ ]]; then
                if mkdir -p "$dest_dir"; then
                    echo "[OK] Created directory: $dest_dir"
                    break
                else
                    echo "[ERROR] Failed to create directory"
                fi
            fi
        else
            echo "[OK] Directory exists and is accessible"
            break
        fi
    done
    
    # Generate config with user's destination
    generate_config
    
    # Update destination in config
    local temp_config=$(mktemp)
    jq --arg dest "$dest_dir" '.destination = $dest' "$CONFIG_PATH" > "$temp_config"
    mv "$temp_config" "$CONFIG_PATH"
    
    echo
    echo "Step 2: Installation Method"
    echo "---------------------------"
    echo "Choose installation method:"
    echo "1. Standard (LaunchAgent/systemd) - Recommended for most directories"
    echo "2. Cron + Screen - Required for Voice Memos and restricted directories"
    echo
    printf "Choose method [1]: "
    read -r method_choice
    method_choice="${method_choice:-1}"
    
    echo
    echo "Step 3: Enable/Disable Watch Directories"
    echo "----------------------------------------"
    echo "Review the configuration file at: $CONFIG_PATH"
    echo "Set 'enabled': true for directories you want to monitor"
    echo
    
    if [[ "$method_choice" == "2" ]]; then
        echo "[OK] Configuration wizard complete!"
        echo "[OK] Edit $CONFIG_PATH to customize your setup"
        echo "[OK] Run '$0 --install-cron' to install with cron + screen method"
    else
        echo "[OK] Configuration wizard complete!"
        echo "[OK] Edit $CONFIG_PATH to customize your setup"
        echo "[OK] Run '$0 --install' to install with standard method"
    fi
}

# Validate configuration
validate_config() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log "ERROR" "Configuration file not found: $CONFIG_PATH"
        log "INFO" "Run '$0 --configure' to create configuration"
        return 1
    fi
    
    if ! jq empty "$CONFIG_PATH" 2>/dev/null; then
        log "ERROR" "Invalid JSON in configuration file"
        return 1
    fi
    
    local destination
    destination=$(jq -r '.destination' "$CONFIG_PATH")
    
    if [[ "$destination" == "null" || -z "$destination" ]]; then
        log "ERROR" "Destination not set in configuration"
        return 1
    fi
    
    # Expand ~ in destination
    destination="${destination/#\~/$HOME}"
    
    if [[ ! -d "$destination" ]]; then
        log "ERROR" "Destination directory does not exist: $destination"
        return 1
    fi
    
    return 0
}

# Check if Voice Memos directory is enabled
voice_memos_enabled() {
    jq -r '.watch_directories[] | select(.name == "voice_memos") | .enabled' "$CONFIG_PATH" 2>/dev/null | grep -q "true"
}

# Process a single file
process_file() {
    local file="$1"
    local tag="$2"
    local destination="$3"
    
    # Get file modification time
    local mtime
    mtime=$($STAT_CMD "$file" 2>/dev/null || echo "0")
    local file_entry="$file:$mtime"
    
    # Check if file has been processed
    if [[ -f "$PROCESSED_DB" ]] && grep -Fxq "$file_entry" "$PROCESSED_DB"; then
        return 0  # Already processed
    fi
    
    # Create destination filename
    local basename
    basename=$(basename "$file")
    local dest_name="[${tag}]_${basename}"
    
    # Add timestamp if file was modified (existed before)
    if [[ -f "$PROCESSED_DB" ]] && grep -Fq "$file:" "$PROCESSED_DB"; then
        local timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
        local name="${basename%.*}"
        local ext="${basename##*.}"
        dest_name="[${tag}]_${name}_${timestamp}.${ext}"
    fi
    
    # Copy file
    local dest_path="$destination/$dest_name"
    if cp "$file" "$dest_path"; then
        log "INFO" "Copied: $(basename "$file") -> $dest_name"
        
        # Update processed database
        mkdir -p "$(dirname "$PROCESSED_DB")"
        if [[ -f "$PROCESSED_DB" ]]; then
            sed -i.bak "/^$(echo "$file" | sed 's/[[\.*^$()+?{|]/\\&/g'):/d" "$PROCESSED_DB" 2>/dev/null || true
        fi
        echo "$file_entry" >> "$PROCESSED_DB"
        return 0
    else
        log "ERROR" "Failed to copy: $file"
        return 1
    fi
}

# Monitor using polling (fallback)
monitor_polling() {
    local destination="$1"
    
    log "INFO" "Using polling-based monitoring (5-second intervals)"
    
    while true; do
        # Read enabled watch directories from config
        local directories
        directories=$(jq -r '.watch_directories[] | select(.enabled == true) | @base64' "$CONFIG_PATH")
        
        while IFS= read -r dir_b64; do
            [[ -z "$dir_b64" ]] && continue
            
            local dir_data
            dir_data=$(echo "$dir_b64" | base64 -d)
            
            local path tag extensions
            path=$(echo "$dir_data" | jq -r '.path')
            tag=$(echo "$dir_data" | jq -r '.tag')
            extensions=$(echo "$dir_data" | jq -r '.extensions[]')
            
            # Expand ~ in path
            path="${path/#\~/$HOME}"
            
            # Skip if directory doesn't exist
            [[ ! -d "$path" ]] && continue
            
            # Find files with matching extensions
            while IFS= read -r ext; do
                [[ -z "$ext" ]] && continue
                
                while IFS= read -r -d '' file; do
                    [[ -f "$file" ]] && process_file "$file" "$tag" "$destination"
                done < <(find "$path" -maxdepth 1 -name "*.$ext" -type f -print0 2>/dev/null || true)
            done <<< "$extensions"
            
        done <<< "$directories"
        
        sleep 5
    done
}

# Monitor using fswatch (macOS)
monitor_fswatch() {
    local destination="$1"
    
    # Get all enabled watch paths
    local watch_paths=()
    
    while IFS= read -r dir_b64; do
        [[ -z "$dir_b64" ]] && continue
        
        local dir_data
        dir_data=$(echo "$dir_b64" | base64 -d)
        
        local path
        path=$(echo "$dir_data" | jq -r '.path')
        path="${path/#\~/$HOME}"
        
        if [[ -d "$path" ]]; then
            watch_paths+=("$path")
        fi
    done < <(jq -r '.watch_directories[] | select(.enabled == true) | @base64' "$CONFIG_PATH")
    
    if [[ ${#watch_paths[@]} -eq 0 ]]; then
        log "WARN" "No valid watch directories found"
        return 1
    fi
    
    log "INFO" "Using fswatch for real-time monitoring"
    log "INFO" "Watching ${#watch_paths[@]} directories"
    
    # Start fswatch
    fswatch -0 "${watch_paths[@]}" | while IFS= read -r -d '' file; do
        [[ ! -f "$file" ]] && continue
        
        # Find which watch directory this file belongs to and get its config
        while IFS= read -r dir_b64; do
            [[ -z "$dir_b64" ]] && continue
            
            local dir_data
            dir_data=$(echo "$dir_b64" | base64 -d)
            
            local watch_path tag extensions
            watch_path=$(echo "$dir_data" | jq -r '.path')
            watch_path="${watch_path/#\~/$HOME}"
            tag=$(echo "$dir_data" | jq -r '.tag')
            extensions=$(echo "$dir_data" | jq -r '.extensions[]')
            
            if [[ "$file" == "$watch_path"/* ]]; then
                # Check if file extension matches
                local file_ext="${file##*.}"
                while IFS= read -r ext; do
                    if [[ "$file_ext" == "$ext" ]]; then
                        process_file "$file" "$tag" "$destination"
                        break 2
                    fi
                done <<< "$extensions"
                break
            fi
        done < <(jq -r '.watch_directories[] | select(.enabled == true) | @base64' "$CONFIG_PATH")
    done
}

# Monitor using inotifywait (Linux)
monitor_inotify() {
    local destination="$1"
    
    # Get all enabled watch paths
    local watch_paths=()
    
    while IFS= read -r dir_b64; do
        [[ -z "$dir_b64" ]] && continue
        
        local dir_data
        dir_data=$(echo "$dir_b64" | base64 -d)
        
        local path
        path=$(echo "$dir_data" | jq -r '.path')
        path="${path/#\~/$HOME}"
        
        if [[ -d "$path" ]]; then
            watch_paths+=("$path")
        fi
    done < <(jq -r '.watch_directories[] | select(.enabled == true) | @base64' "$CONFIG_PATH")
    
    if [[ ${#watch_paths[@]} -eq 0 ]]; then
        log "WARN" "No valid watch directories found"
        return 1
    fi
    
    log "INFO" "Using inotifywait for real-time monitoring"
    log "INFO" "Watching ${#watch_paths[@]} directories"
    
    # Start inotifywait
    inotifywait -m -e close_write,moved_to --format '%w%f' "${watch_paths[@]}" | while read -r file; do
        [[ ! -f "$file" ]] && continue
        
        # Find which watch directory this file belongs to and get its config
        while IFS= read -r dir_b64; do
            [[ -z "$dir_b64" ]] && continue
            
            local dir_data
            dir_data=$(echo "$dir_b64" | base64 -d)
            
            local watch_path tag extensions
            watch_path=$(echo "$dir_data" | jq -r '.path')
            watch_path="${watch_path/#\~/$HOME}"
            tag=$(echo "$dir_data" | jq -r '.tag')
            extensions=$(echo "$dir_data" | jq -r '.extensions[]')
            
            if [[ "$file" == "$watch_path"/* ]]; then
                # Check if file extension matches
                local file_ext="${file##*.}"
                while IFS= read -r ext; do
                    if [[ "$file_ext" == "$ext" ]]; then
                        process_file "$file" "$tag" "$destination"
                        break 2
                    fi
                done <<< "$extensions"
                break
            fi
        done < <(jq -r '.watch_directories[] | select(.enabled == true) | @base64' "$CONFIG_PATH")
    done
}

# Setup configuration files without installing
setup_config() {
    log "INFO" "Setting up configuration files..."
    
    # Generate configuration if it doesn't exist
    if [[ ! -f "$CONFIG_PATH" ]]; then
        generate_config
        log "INFO" "Generated default configuration at $CONFIG_PATH"
    else
        log "INFO" "Configuration already exists at $CONFIG_PATH"
    fi
    
    # Generate .env file if it doesn't exist
    if [[ ! -f "$ENV_PATH" ]]; then
        generate_env
        log "INFO" "Generated default .env file at $ENV_PATH"
    else
        log "INFO" ".env file already exists at $ENV_PATH"
    fi
    
    echo
    echo "Setup Complete!"
    echo "==============="
    echo "Configuration: $CONFIG_PATH"
    echo "Environment:   $ENV_PATH"
    echo
    echo "You can now run manually with:"
    echo "  $0 --monitor"
    echo "Or with arguments:"
    echo "  $0 --monitor --source ~/Downloads --dest ~/organized --tag download --ext pdf,jpg"
}

# Monitor with manual arguments (no config files required)
monitor_manual() {
    local source_dir="${DTT_SOURCE_DIR:-}"
    local dest_dir="${DTT_DEST_DIR:-}"
    local file_tag="${DTT_FILE_TAG:-manual}"
    local extensions="${DTT_EXTENSIONS:-pdf,jpg,png,doc,docx}"
    local poll_interval="${DTT_POLL_INTERVAL:-5}"
    
    # Validate required parameters
    if [[ -z "$source_dir" || -z "$dest_dir" ]]; then
        log "ERROR" "Manual mode requires source and destination directories"
        echo "Usage: $0 --monitor --source <dir> --dest <dir> [--tag <tag>] [--ext <extensions>]"
        echo "Or set environment variables: DTT_SOURCE_DIR, DTT_DEST_DIR"
        exit 1
    fi
    
    # Expand ~ in paths
    source_dir="${source_dir/#\~/$HOME}"
    dest_dir="${dest_dir/#\~/$HOME}"
    
    # Validate directories
    if [[ ! -d "$source_dir" ]]; then
        log "ERROR" "Source directory does not exist: $source_dir"
        exit 1
    fi
    
    # Create destination directory if it doesn't exist
    if [[ ! -d "$dest_dir" ]]; then
        if [[ "${DTT_AUTO_CREATE_DIRS:-true}" == "true" ]]; then
            mkdir -p "$dest_dir"
            log "INFO" "Created destination directory: $dest_dir"
        else
            log "ERROR" "Destination directory does not exist: $dest_dir"
            exit 1
        fi
    fi
    
    log "INFO" "Starting Deep Thought Trillian v$VERSION (Manual Mode)"
    log "INFO" "Source: $source_dir"
    log "INFO" "Destination: $dest_dir"
    log "INFO" "Tag: $file_tag"
    log "INFO" "Extensions: $extensions"
    log "INFO" "Poll interval: ${poll_interval}s"
    
    # Convert extensions to array
    IFS=',' read -ra ext_array <<< "$extensions"
    
    # Store PID
    echo $ > "$PID_FILE"
    
    # Set up signal handlers
    trap 'log "INFO" "Shutting down..."; rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT
    
    # Simple polling loop for manual mode
    while true; do
        for ext in "${ext_array[@]}"; do
            ext="${ext// /}"  # Remove spaces
            [[ -z "$ext" ]] && continue
            
            while IFS= read -r -d '' file; do
                [[ -f "$file" ]] && process_file "$file" "$file_tag" "$dest_dir"
            done < <(find "$source_dir" -maxdepth 1 -name "*.$ext" -type f -print0 2>/dev/null || true)
        done
        
        sleep "$poll_interval"
    done
}

# Main monitoring function
start_monitoring() {
    # Parse command-line arguments first
    parse_arguments "$@"
    
    # Check if we have manual mode parameters
    if [[ -n "${DTT_SOURCE_DIR:-}" && -n "${DTT_DEST_DIR:-}" ]]; then
        monitor_manual
        return
    fi
    
    # Load environment variables
    load_env
    
    # Check again after loading .env
    if [[ -n "${DTT_SOURCE_DIR:-}" && -n "${DTT_DEST_DIR:-}" ]]; then
        monitor_manual
        return
    fi
    
    # Fall back to config-based monitoring
    # Validate configuration
    if ! validate_config; then
        log "ERROR" "No configuration found and no manual parameters provided"
        log "INFO" "Run '$0 --setup' to create configuration files"
        log "INFO" "Or use manual mode: $0 --monitor --source <dir> --dest <dir>"
        exit 1
    fi
    
    # Get destination from config, with .env override
    local destination
    destination=$(jq -r '.destination' "$CONFIG_PATH")
    destination="${destination/#\~/$HOME}"
    
    # Override with environment variable if set
    if [[ -n "${DTT_DEST_DIR:-}" ]]; then
        destination="${DTT_DEST_DIR/#\~/$HOME}"
        log "INFO" "Using destination from DTT_DEST_DIR: $destination"
    fi
    
    log "INFO" "Starting Deep Thought Trillian v$VERSION"
    log "INFO" "Destination: $destination"
    log "INFO" "OS: $OS_TYPE"
    
    # Create processed files database
    mkdir -p "$(dirname "$PROCESSED_DB")"
    touch "$PROCESSED_DB"
    
    # Store PID
    echo $$ > "$PID_FILE"
    
    # Set up signal handlers
    trap 'log "INFO" "Shutting down..."; rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT
    
    # Choose monitoring method based on available tools
    case "$OS_TYPE" in
        "macos")
            if command_exists fswatch; then
                monitor_fswatch "$destination"
            else
                log "WARN" "fswatch not found - install with 'brew install fswatch' for real-time monitoring"
                log "INFO" "Currently using 5-second polling (fswatch provides instant file detection)"
                monitor_polling "$destination"
            fi
            ;;
        "linux")
            if command_exists inotifywait; then
                monitor_inotify "$destination"
            else
                log "WARN" "inotifywait not available, falling back to polling"
                monitor_polling "$destination"
            fi
            ;;
        *)
            log "WARN" "Unknown OS, using polling method"
            monitor_polling "$destination"
            ;;
    esac
}

# Create cron wrapper script
create_cron_wrapper() {
    local script_path
    script_path=$(realpath "$0")
    
    cat > "$CRON_WRAPPER" << EOF
#!/bin/bash

# Cron wrapper for Deep Thought Trillian
# This script ensures the screen session is always running

SCRIPT_PATH="$script_path"
CONFIG_DIR="$CONFIG_DIR"
CRON_LOG="$CRON_LOG"
SCREEN_PID="$SCREEN_PID"
CRON_STATUS="$CRON_STATUS"

# Function to log messages
cron_log() {
    local level="\$1"
    shift
    local message="\$*"
    local timestamp="[\$(date +"%Y-%m-%d %H:%M:%S")]"
    echo "\$timestamp [\$level] \$message" >> "\$CRON_LOG"
}

# Check if screen session exists
screen_session_exists() {
    screen -list 2>/dev/null | grep -q "deep-thought-trillian"
}

# Get screen session PID
get_screen_session_pid() {
    screen -list 2>/dev/null | grep "deep-thought-trillian" | cut -d. -f1 | tr -d '\t' 2>/dev/null || echo ""
}

# Update status file
update_status() {
    local status="\$1"
    echo "status=\$status" > "\$CRON_STATUS"
    echo "last_check=\$(date +%s)" >> "\$CRON_STATUS"
    if screen_session_exists; then
        echo "screen_pid=\$(get_screen_session_pid)" >> "\$CRON_STATUS"
    fi
}

# Main logic
if ! screen_session_exists; then
    cron_log "INFO" "Screen session not found, starting new session"
    screen -dmS deep-thought-trillian "\$SCRIPT_PATH" --monitor
    sleep 2
    
    if screen_session_exists; then
        local pid=\$(get_screen_session_pid)
        echo "\$pid" > "\$SCREEN_PID"
        cron_log "INFO" "Started screen session with PID: \$pid"
        update_status "running"
    else
        cron_log "ERROR" "Failed to start screen session"
        update_status "failed"
    fi
else
    local pid=\$(get_screen_session_pid)
    if [[ -n "\$pid" ]]; then
        echo "\$pid" > "\$SCREEN_PID"
        update_status "running"
    fi
fi
EOF
    
    chmod +x "$CRON_WRAPPER"
    log "INFO" "Created cron wrapper script: $CRON_WRAPPER"
}

# Install cron job
install_cron_job() {
    local current_crontab
    local new_cron_line="* * * * * $CRON_WRAPPER >/dev/null 2>&1"
    
    # Get current crontab (ignore errors if no crontab exists)
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # Check if our cron job already exists
    if echo "$current_crontab" | grep -q "$CRON_WRAPPER"; then
        log "INFO" "Cron job already exists"
        return 0
    fi
    
    # Add our cron job
    {
        echo "$current_crontab"
        echo "$new_cron_line"
    } | crontab -
    
    log "INFO" "Installed cron job for Deep Thought Trillian"
}

# Remove cron job
remove_cron_job() {
    local current_crontab
    local temp_crontab
    
    # Get current crontab (ignore errors if no crontab exists)
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # Remove our cron job
    temp_crontab=$(echo "$current_crontab" | grep -v "$CRON_WRAPPER" || true)
    
    if [[ -n "$temp_crontab" ]]; then
        echo "$temp_crontab" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
    
    log "INFO" "Removed cron job for Deep Thought Trillian"
}

# Install as system service
install_service() {
    local script_path
    script_path=$(realpath "$0")
    
    mkdir -p "$SERVICE_DIR"
    
    case "$SERVICE_TYPE" in
        "launchd")
            cat > "$SERVICE_DIR/$SERVICE_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.deep-thought-trillian</string>
    <key>ProgramArguments</key>
    <array>
        <string>$script_path</string>
        <string>--monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF
            
            # Load the service
            launchctl unload "$SERVICE_DIR/$SERVICE_FILE" 2>/dev/null || true
            launchctl load "$SERVICE_DIR/$SERVICE_FILE"
            
            log "INFO" "Installed as LaunchAgent: $SERVICE_DIR/$SERVICE_FILE"
            ;;
            
        "systemd")
            cat > "$SERVICE_DIR/$SERVICE_FILE" << EOF
[Unit]
Description=Deep Thought Trillian File Monitor
After=network.target

[Service]
Type=simple
ExecStart=$script_path --monitor
Restart=always
RestartSec=10
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=default.target
EOF
            
            # Reload and enable the service
            systemctl --user daemon-reload
            systemctl --user enable "$SERVICE_FILE"
            systemctl --user start "$SERVICE_FILE"
            
            log "INFO" "Installed as systemd service: $SERVICE_DIR/$SERVICE_FILE"
            ;;
            
        *)
            log "ERROR" "Service installation not supported on this system"
            return 1
            ;;
    esac
}

# Install cron-based monitoring
install_cron_service() {
    log "INFO" "Installing cron-based monitoring with screen..."
    
    # Check dependencies
    check_dependencies
    
    # Generate configuration if it doesn't exist
    if [[ ! -f "$CONFIG_PATH" ]]; then
        generate_config
        log "INFO" "Generated default configuration"
        log "INFO" "Edit $CONFIG_PATH to customize your setup"
    fi
    
    # Generate .env file if it doesn't exist
    if [[ ! -f "$ENV_PATH" ]]; then
        generate_env
    fi
    
    # Create cron wrapper script
    create_cron_wrapper
    
    # Install cron job
    install_cron_job
    
    # Initialize status file
    echo "status=installed" > "$CRON_STATUS"
    echo "last_check=$(date +%s)" >> "$CRON_STATUS"
    echo "install_time=$(date)" >> "$CRON_STATUS"
    
    log "INFO" "Cron-based monitoring installed successfully"
    
    echo
    echo "Cron Installation Complete!"
    echo "=========================="
    echo
    echo "Installation method: Cron + Screen (bypasses LaunchAgent restrictions)"
    echo "Configuration: $CONFIG_PATH"
    echo "Logs: $LOG_FILE"
    echo "Cron logs: $CRON_LOG"
    echo "Status: $CRON_STATUS"
    echo
    echo "[OK] Cron job checks every minute for screen session"
    echo "[OK] Screen session runs the monitoring in background"
    echo "[OK] Bypasses macOS security restrictions for Voice Memos"
    echo
    echo "Next steps:"
    echo "1. Edit configuration: $CONFIG_PATH"
    echo "2. Enable directories you want to monitor"
    echo "3. Check status: $0 --status-cron"
    echo "4. View logs: tail -f $LOG_FILE"
    echo "5. View cron logs: tail -f $CRON_LOG"
}

# Uninstall
uninstall_cron_service() {
    log "INFO" "Uninstalling cron-based monitoring..."
    
    # Stop screen session
    if screen_session_exists; then
        local pid=$(get_screen_session_pid)
        if [[ -n "$pid" ]]; then
            screen -S deep-thought-trillian -X quit
            log "INFO" "Stopped screen session (PID: $pid)"
        fi
    fi
    
    # Remove cron job
    remove_cron_job
    
    # Remove cron files
    [[ -f "$CRON_WRAPPER" ]] && rm -f "$CRON_WRAPPER"
    [[ -f "$SCREEN_PID" ]] && rm -f "$SCREEN_PID"
    [[ -f "$CRON_STATUS" ]] && rm -f "$CRON_STATUS"
    
    log "INFO" "Cron-based monitoring uninstalled successfully"
}

# Uninstall service
uninstall_service() {
    case "$SERVICE_TYPE" in
        "launchd")
            if [[ -f "$SERVICE_DIR/$SERVICE_FILE" ]]; then
                launchctl unload "$SERVICE_DIR/$SERVICE_FILE" 2>/dev/null || true
                rm -f "$SERVICE_DIR/$SERVICE_FILE"
                log "INFO" "Uninstalled LaunchAgent"
            fi
            ;;
            
        "systemd")
            if [[ -f "$SERVICE_DIR/$SERVICE_FILE" ]]; then
                systemctl --user stop "$SERVICE_FILE" 2>/dev/null || true
                systemctl --user disable "$SERVICE_FILE" 2>/dev/null || true
                rm -f "$SERVICE_DIR/$SERVICE_FILE"
                systemctl --user daemon-reload
                log "INFO" "Uninstalled systemd service"
            fi
            ;;
    esac
    
    # Clean up PID file
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
}

# Show cron status
show_cron_status() {
    echo "Deep Thought Trillian v$VERSION - Cron Mode"
    echo "==========================================="
    echo "OS: $OS_TYPE"
    echo "Config: $CONFIG_PATH"
    echo "Log: $LOG_FILE"
    echo "Cron Log: $CRON_LOG"
    echo
    
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "Status: Not configured"
        echo "Run '$0 --configure' to set up"
        return
    fi
    
    echo "Configuration:"
    local destination
    destination=$(jq -r '.destination' "$CONFIG_PATH" 2>/dev/null || echo "Invalid config")
    echo "  Destination: $destination"
    echo
    
    echo "Watch Directories:"
    jq -r '.watch_directories[] | "  [\(.tag)] \(.path) (\(.extensions | join(", "))) - \(if .enabled then "ENABLED" else "DISABLED" end)"' "$CONFIG_PATH" 2>/dev/null || echo "  Invalid configuration"
    echo
    
    # Check cron job status
    if crontab -l 2>/dev/null | grep -q "$CRON_WRAPPER"; then
        echo "Cron Job: Installed"
    else
        echo "Cron Job: Not installed"
    fi
    
    # Check screen session
    if screen_session_exists; then
        local pid=$(get_screen_session_pid)
        echo "Screen Session: Running (PID: $pid)"
    else
        echo "Screen Session: Stopped"
    fi
    
    # Check status file
    if [[ -f "$CRON_STATUS" ]]; then
        echo "Status File:"
        while IFS='=' read -r key value; do
            case "$key" in
                "status") echo "  Status: $value" ;;
                "last_check") echo "  Last Check: $(date -r "$value" 2>/dev/null || echo "$value")" ;;
                "install_time") echo "  Installed: $value" ;;
                "screen_pid") echo "  Screen PID: $value" ;;
            esac
        done < "$CRON_STATUS"
    else
        echo "Status File: Not found"
    fi
}

# Show current status
show_status() {
    echo "Deep Thought Trillian v$VERSION"
    echo "=============================="
    echo "OS: $OS_TYPE"
    echo "Config: $CONFIG_PATH"
    echo "Log: $LOG_FILE"
    echo
    
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "Status: Not configured"
        echo "Run '$0 --configure' to set up"
        return
    fi
    
    echo "Configuration:"
    local destination
    destination=$(jq -r '.destination' "$CONFIG_PATH" 2>/dev/null || echo "Invalid config")
    echo "  Destination: $destination"
    echo
    
    echo "Watch Directories:"
    jq -r '.watch_directories[] | "  [\(.tag)] \(.path) (\(.extensions | join(", "))) - \(if .enabled then "ENABLED" else "DISABLED" end)"' "$CONFIG_PATH" 2>/dev/null || echo "  Invalid configuration"
    echo
    
    # Check if running
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Status: Running (PID: $(cat "$PID_FILE"))"
    else
        echo "Status: Stopped"
    fi
    
    # Check service status
    case "$SERVICE_TYPE" in
        "launchd")
            if [[ -f "$SERVICE_DIR/$SERVICE_FILE" ]]; then
                echo "Service: Installed (LaunchAgent)"
            else
                echo "Service: Not installed"
            fi
            ;;
        "systemd")
            if [[ -f "$SERVICE_DIR/$SERVICE_FILE" ]]; then
                echo "Service: Installed (systemd)"
                systemctl --user is-active "$SERVICE_FILE" 2>/dev/null && echo "Service Status: Active" || echo "Service Status: Inactive"
            else
                echo "Service: Not installed"
            fi
            ;;
        *)
            echo "Service: Not supported on this OS"
            ;;
    esac
    
    # Check cron status
    if crontab -l 2>/dev/null | grep -q "$CRON_WRAPPER"; then
        echo "Cron Job: Installed"
        if screen_session_exists; then
            echo "Screen Session: Running"
        else
            echo "Screen Session: Stopped"
        fi
    fi
}

# Complete installation process
install_complete() {
    log "INFO" "Starting complete installation..."
    
    # Check dependencies
    check_dependencies
    
    # Generate configuration if it doesn't exist
    if [[ ! -f "$CONFIG_PATH" ]]; then
        generate_config
        log "INFO" "Generated default configuration"
        log "INFO" "Edit $CONFIG_PATH to customize your setup"
    fi
    
    # Check if Voice Memos is enabled and recommend cron installation
    if voice_memos_enabled 2>/dev/null; then
        echo
        echo "[WARNING] Voice Memos Detected!"
        echo "Voice Memos directory is enabled in your configuration."
        echo "Due to macOS security restrictions, LaunchAgent may not work with Voice Memos."
        echo
        echo "Recommendation: Use cron installation instead"
        echo "Run: $0 --install-cron"
        echo
        printf "Continue with standard installation anyway? (y/n) [n]: "
        read -r continue_standard
        if [[ ! "$continue_standard" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled. Use --install-cron for Voice Memos support."
            exit 0
        fi
    fi
    
    # Install service
    install_service
    
    echo
    echo "Installation Complete!"
    echo "====================="
    echo
    case "$OS_TYPE" in
        "macos")
            echo "macOS Permissions Required:"
            echo "1. Open System Preferences > Security & Privacy > Privacy"
            echo "2. Add Terminal (or your terminal app) to:"
            echo "   - Full Disk Access"
            echo "   - Files and Folders"
            echo "3. Grant access to directories you want to monitor"
            echo
            if voice_memos_enabled 2>/dev/null; then
                echo "[WARNING] Voice Memos Note:"
                echo "If you experience 'Operation not permitted' errors with Voice Memos,"
                echo "uninstall this service and use cron installation instead:"
                echo "  $0 --uninstall"
                echo "  $0 --install-cron"
                echo
            fi
            ;;
        "linux")
            echo "Linux Setup:"
            echo "- Service installed and started automatically"
            echo "- Check status with: systemctl --user status deep-thought-trillian"
            echo
            ;;
    esac
    echo "Configuration: $CONFIG_PATH"
    echo "Logs: $LOG_FILE"
    echo
    echo "Next steps:"
    echo "1. Edit configuration: $CONFIG_PATH"
    echo "2. Enable directories you want to monitor"
    echo "3. Check status: $0 --status"
    echo "4. View logs: tail -f $LOG_FILE"
}

# Stop monitoring
stop_monitoring() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid"
        rm -f "$PID_FILE"
        log "INFO" "Stopped monitoring (PID: $pid)"
    else
        log "WARN" "Not currently running"
    fi
}

# Restart monitoring
restart_monitoring() {
    stop_monitoring
    sleep 2
    start_monitoring
}

# Start cron monitoring
start_cron_monitoring() {
    if screen_session_exists; then
        echo "Screen session already running"
        screen -list | grep "deep-thought-trillian"
    else
        screen -dmS deep-thought-trillian "$0" --monitor
        sleep 2
        if screen_session_exists; then
            local pid=$(get_screen_session_pid)
            echo "Started screen session with PID: $pid"
            echo "To attach: screen -r deep-thought-trillian"
            echo "To detach: Ctrl+A, then D"
        else
            echo "Failed to start screen session"
        fi
    fi
}

# Stop cron monitoring
stop_cron_monitoring() {
    if screen_session_exists; then
        local pid=$(get_screen_session_pid)
        screen -S deep-thought-trillian -X quit
        echo "Stopped screen session (PID: $pid)"
    else
        echo "No screen session running"
    fi
}

# Show help
show_help() {
    cat << EOF
Deep Thought Trillian v$VERSION - Automatic File Organization

USAGE:
    $0 [COMMAND]

INSTALLATION COMMANDS:
    --install           Complete installation (dependencies, config, LaunchAgent/systemd)
    --install-cron      Install with cron + screen (bypasses LaunchAgent restrictions)
    --configure         Interactive configuration wizard
    --setup             Create config files without installing service

MONITORING COMMANDS:
    --monitor           Start monitoring (foreground)
    --monitor [options] Start manual monitoring with arguments
    --status            Show current status
    --start             Start monitoring service
    --stop              Stop monitoring service  
    --restart           Restart monitoring service
    --uninstall         Remove service and stop monitoring

MANUAL MONITORING OPTIONS:
    -s, --source <dir>  Source directory to monitor
    -d, --dest <dir>    Destination directory for organized files
    -t, --tag <tag>     Tag prefix for files (default: manual)
    -e, --ext <list>    File extensions (comma-separated, default: pdf,jpg,png,doc,docx)
    -l, --log-level     Log level (DEBUG, INFO, WARN, ERROR)
    -p, --poll <sec>    Polling interval in seconds (default: 5)

CRON SERVICE COMMANDS:
    --status-cron       Show cron service status
    --start-cron        Start screen session for monitoring
    --stop-cron         Stop screen session
    --uninstall-cron    Remove cron job and stop monitoring

GENERAL COMMANDS:
    --help              Show this help message

INSTALLATION METHODS:
    1. Standard (--install)
       - Uses LaunchAgent (macOS) or systemd (Linux)
       - Recommended for most directories
       - May have restrictions with Voice Memos on macOS

    2. Cron + Screen (--install-cron)
       - Uses cron job + screen session
       - Required for Voice Memos and restricted directories
       - Bypasses macOS security restrictions

EXAMPLES:
    $0 --install            # Standard installation
    $0 --install-cron       # Cron installation (for Voice Memos)
    $0 --configure          # Set up configuration
    $0 --setup              # Create config files only
    $0 --monitor            # Run with config files
    $0 --monitor --source ~/Downloads --dest ~/organized --tag download --ext pdf,jpg
    DTT_SOURCE_DIR=~/Downloads DTT_DEST_DIR=~/organized $0 --monitor
    $0 --status             # Check standard service status
    $0 --status-cron        # Check cron service status

FILES:
    Config:      $CONFIG_PATH
    Log:         $LOG_FILE
    Cron Log:    $CRON_LOG
    PID:         $PID_FILE

For more information, see the README.md file.
EOF
}

# Main execution
main() {
    case "${1:-}" in
        --install)
            install_complete
            ;;
        --install-cron)
            install_cron_service
            ;;
        --configure)
            configure_interactive
            ;;
        --setup)
            setup_config
            ;;
        --monitor)
            start_monitoring
            ;;
        --status)
            show_status
            ;;
        --status-cron)
            show_cron_status
            ;;
        --start)
            case "$SERVICE_TYPE" in
                "launchd") launchctl load "$SERVICE_DIR/$SERVICE_FILE" ;;
                "systemd") systemctl --user start "$SERVICE_FILE" ;;
                *) log "ERROR" "Service not supported" ;;
            esac
            ;;
        --stop)
            case "$SERVICE_TYPE" in
                "launchd") launchctl unload "$SERVICE_DIR/$SERVICE_FILE" ;;
                "systemd") systemctl --user stop "$SERVICE_FILE" ;;
                *) stop_monitoring ;;
            esac
            ;;
        --restart)
            case "$SERVICE_TYPE" in
                "launchd") 
                    launchctl unload "$SERVICE_DIR/$SERVICE_FILE" 2>/dev/null || true
                    launchctl load "$SERVICE_DIR/$SERVICE_FILE"
                    ;;
                "systemd") systemctl --user restart "$SERVICE_FILE" ;;
                *) restart_monitoring ;;
            esac
            ;;
        --start-cron)
            start_cron_monitoring
            ;;
        --stop-cron)
            stop_cron_monitoring
            ;;
        --uninstall)
            uninstall_service
            ;;
        --uninstall-cron)
            uninstall_cron_service
            ;;
        --help|-h)
            show_help
            ;;
        "")
            show_status
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
