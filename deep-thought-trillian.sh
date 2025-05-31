#!/bin/bash

# Script: deep-thought-trillian.sh
# Description: Advanced file monitoring and organization system with API upload support
# Version: 1.1.1
# Supports: macOS and Ubuntu/Linux with LaunchAgent/systemd and cron variants
# New: HTTP Basic Auth API upload functionality

set -euo pipefail

# Constants
readonly SCRIPT_NAME="deep-thought-trillian"
readonly VERSION="1.1.1"
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

# API Upload Configuration
# DTT_API_UPLOAD_ENABLED=false
# DTT_API_ENDPOINT=https://api.deep-thought.cloud/api/v1/transcribe
# DTT_API_USERNAME=
# DTT_API_PASSWORD=
# DTT_API_UPLOAD_MODE=copy_and_upload
# DTT_API_TIMEOUT=30
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
            --api-endpoint)
                DTT_API_ENDPOINT="$2"
                shift 2
                ;;
            --api-username)
                DTT_API_USERNAME="$2"
                shift 2
                ;;
            --api-password)
                DTT_API_PASSWORD="$2"
                shift 2
                ;;
            --upload-mode)
                DTT_API_UPLOAD_MODE="$2"
                shift 2
                ;;
            --api-upload)
                DTT_API_UPLOAD_ENABLED=true
                shift
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
    
    # Check for curl (required for API uploads)
    if ! command_exists curl; then
        missing_deps+=("curl")
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
  "api_upload": {
    "enabled": false,
    "endpoint": "https://api.deep-thought.cloud/api/v1/transcribe",
    "username": "",
    "password": "",
    "upload_mode": "copy_and_upload",
    "timeout": 30
  },
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

# Upload file to API using HTTP Basic Auth
upload_file_to_api() {
    local file="$1"
    local tag="$2"
    local api_endpoint="$3"
    local username="$4"
    local password="$5"
    local timeout="${6:-30}"
    
    # Validate inputs
    if [[ ! -f "$file" ]]; then
        log "ERROR" "Upload failed: file does not exist: $file"
        return 1
    fi
    
    if [[ -z "$api_endpoint" || -z "$username" || -z "$password" ]]; then
        log "ERROR" "Upload failed: missing API endpoint, username, or password"
        return 1
    fi
    
    local basename
    basename=$(basename "$file")
    
    log "INFO" "Uploading file to API: $basename"
    log "DEBUG" "API endpoint: $api_endpoint"
    log "DEBUG" "Username: $username"
    log "DEBUG" "Tag: $tag"
    
    # Create temporary response file
    local response_file
    response_file=$(mktemp)
    
    # Upload file using curl with HTTP Basic Auth
    local curl_exit_code=0
    local http_status
    
    http_status=$(curl -w "%{http_code}" \
        -u "$username:$password" \
        -X POST \
        -F "file=@$file" \
        -F "tag=$tag" \
        --connect-timeout "$timeout" \
        --max-time $((timeout * 2)) \
        -s \
        -o "$response_file" \
        "$api_endpoint") || curl_exit_code=$?
    
    # Check curl exit code
    if [[ $curl_exit_code -ne 0 ]]; then
        log "ERROR" "Upload failed: curl error (exit code: $curl_exit_code) for file: $basename"
        rm -f "$response_file"
        return 1
    fi
    
    # Check HTTP status code
    if [[ "$http_status" -ge 200 && "$http_status" -lt 300 ]]; then
        # Success - parse response for task ID if available
        local task_id=""
        if command_exists jq && [[ -s "$response_file" ]]; then
            task_id=$(jq -r '.task_id // .id // empty' "$response_file" 2>/dev/null || echo "")
        fi
        
        if [[ -n "$task_id" ]]; then
            log "INFO" "Upload successful: $basename -> Task ID: $task_id"
        else
            log "INFO" "Upload successful: $basename (HTTP $http_status)"
        fi
        
        # Log response for debugging
        if [[ -s "$response_file" ]]; then
            log "DEBUG" "API response: $(cat "$response_file")"
        fi
        
        rm -f "$response_file"
        return 0
    else
        # Error - log response
        local error_msg="Unknown error"
        if [[ -s "$response_file" ]]; then
            if command_exists jq; then
                error_msg=$(jq -r '.error // .message // empty' "$response_file" 2>/dev/null || cat "$response_file")
            else
                error_msg=$(cat "$response_file")
            fi
        fi
        
        log "ERROR" "Upload failed: $basename (HTTP $http_status) - $error_msg"
        rm -f "$response_file"
        return 1
    fi
}

# Get API configuration from config file and environment
get_api_config() {
    local api_enabled="${DTT_API_UPLOAD_ENABLED:-false}"
    local api_endpoint="${DTT_API_ENDPOINT:-https://api.deep-thought.cloud/api/v1/transcribe}"
    local api_username="${DTT_API_USERNAME:-}"
    local api_password="${DTT_API_PASSWORD:-}"
    local api_upload_mode="${DTT_API_UPLOAD_MODE:-copy_and_upload}"
    local api_timeout="${DTT_API_TIMEOUT:-30}"
    
    # Override with config file values if available
    if [[ -f "$CONFIG_PATH" ]] && command_exists jq; then
        local config_enabled
        config_enabled=$(jq -r '.api_upload.enabled // false' "$CONFIG_PATH" 2>/dev/null)
        if [[ "$config_enabled" == "true" && "$api_enabled" != "true" ]]; then
            api_enabled="true"
        fi
        
        if [[ -z "$api_endpoint" ]]; then
            api_endpoint=$(jq -r '.api_upload.endpoint // empty' "$CONFIG_PATH" 2>/dev/null)
        fi
        
        if [[ -z "$api_username" ]]; then
            api_username=$(jq -r '.api_upload.username // empty' "$CONFIG_PATH" 2>/dev/null)
        fi
        
        if [[ -z "$api_password" ]]; then
            api_password=$(jq -r '.api_upload.password // empty' "$CONFIG_PATH" 2>/dev/null)
        fi
        
        if [[ "$api_upload_mode" == "copy_and_upload" ]]; then
            local config_mode
            config_mode=$(jq -r '.api_upload.upload_mode // "copy_and_upload"' "$CONFIG_PATH" 2>/dev/null)
            api_upload_mode="$config_mode"
        fi
        
        if [[ "$api_timeout" == "30" ]]; then
            local config_timeout
            config_timeout=$(jq -r '.api_upload.timeout // 30' "$CONFIG_PATH" 2>/dev/null)
            api_timeout="$config_timeout"
        fi
    fi
    
    # Export for use in other functions
    export API_UPLOAD_ENABLED="$api_enabled"
    export API_ENDPOINT="$api_endpoint"
    export API_USERNAME="$api_username"
    export API_PASSWORD="$api_password"
    export API_UPLOAD_MODE="$api_upload_mode"
    export API_TIMEOUT="$api_timeout"
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
    echo "Step 2: API Upload Configuration (Optional)"
    echo "------------------------------------------"
    echo "Configure API upload to Deep Thought server?"
    printf "Enable API upload? (y/n) [n]: "
    read -r enable_api
    
    if [[ "$enable_api" =~ ^[Yy]$ ]]; then
        echo
        printf "API endpoint [https://api.deep-thought.cloud/api/v1/transcribe]: "
        read -r api_endpoint
        api_endpoint="${api_endpoint:-https://api.deep-thought.cloud/api/v1/transcribe}"
        
        printf "API username: "
        read -r api_username
        
        printf "API password: "
        read -rs api_password
        echo
        
        echo "Upload modes:"
        echo "1. copy_only - Only copy files locally (original behavior)"
        echo "2. upload_only - Only upload to API, no local copy"
        echo "3. copy_and_upload - Both copy locally and upload to API"
        printf "Choose upload mode [3]: "
        read -r mode_choice
        
        local upload_mode="copy_and_upload"
        case "$mode_choice" in
            1) upload_mode="copy_only" ;;
            2) upload_mode="upload_only" ;;
            3|"") upload_mode="copy_and_upload" ;;
        esac
        
        # Update config with API settings
        temp_config=$(mktemp)
        jq --arg endpoint "$api_endpoint" \
           --arg username "$api_username" \
           --arg password "$api_password" \
           --arg mode "$upload_mode" \
           '.api_upload.enabled = true | 
            .api_upload.endpoint = $endpoint | 
            .api_upload.username = $username | 
            .api_upload.password = $password | 
            .api_upload.upload_mode = $mode' \
           "$CONFIG_PATH" > "$temp_config"
        mv "$temp_config" "$CONFIG_PATH"
        
        echo "[OK] API upload configured"
    fi
    
    echo
    echo "Step 3: Installation Method"
    echo "---------------------------"
    echo "Choose installation method:"
    echo "1. Standard (LaunchAgent/systemd) - Recommended for most directories"
    echo "2. Cron + Screen - Required for Voice Memos and restricted directories"
    echo
    printf "Choose method [1]: "
    read -r method_choice
    method_choice="${method_choice:-1}"
    
    echo
    echo "Step 4: Enable/Disable Watch Directories"
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

# Detect Voice Memos folder and count files
detect_voice_memos() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        local voice_memos_path="$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
        if [[ -d "$voice_memos_path" ]]; then
            local count=$(find "$voice_memos_path" -name "*.m4a" 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$count" -gt 0 ]]; then
                echo "Voice Memos ($count recordings found)"
            else
                echo "Voice Memos (folder exists)"
            fi
            return 0
        fi
    fi
    return 1
}

# Test API connection
test_api_connection() {
    local endpoint="$1"
    local username="$2"
    local password="$3"
    
    if [[ -z "$endpoint" || -z "$username" || -z "$password" ]]; then
        return 1
    fi
    
    # Simple connection test
    local http_code
    http_code=$(curl -s -w "%{http_code}" -u "$username:$password" \
        --connect-timeout 10 --max-time 15 \
        -X GET "$endpoint" -o /dev/null 2>/dev/null || echo "000")
    
    # Accept various success codes (200, 405 for method not allowed, etc.)
    if [[ "$http_code" =~ ^(200|405|404)$ ]]; then
        return 0
    else
        return 1
    fi
}

# Generate minimal API-only config
generate_api_config() {
    local endpoint="$1"
    local username="$2"
    local password="$3"
    local source_path="$4"
    local tag="${5:-upload}"
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_PATH" << EOF
{
  "destination": "/tmp/unused",
  "api_upload": {
    "enabled": true,
    "endpoint": "$endpoint",
    "username": "$username",
    "password": "$password",
    "upload_mode": "upload_only",
    "timeout": 30
  },
  "watch_directories": [
    {
      "name": "api_monitor",
      "path": "$source_path",
      "extensions": ["pdf", "m4a", "wav"],
      "tag": "$tag",
      "enabled": true
    }
  ]
}
EOF
    
    log "INFO" "Generated API-only configuration at $CONFIG_PATH"
}

# Generate minimal local-only config
generate_local_config() {
    local source_path="$1"
    local dest_path="$2"
    local extensions="$3"
    local tag="${4:-local}"
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_PATH" << EOF
{
  "destination": "$dest_path",
  "api_upload": {
    "enabled": false,
    "endpoint": "https://api.deep-thought.cloud/api/v1/transcribe",
    "username": "",
    "password": "",
    "upload_mode": "copy_only",
    "timeout": 30
  },
  "watch_directories": [
    {
      "name": "local_monitor",
      "path": "$source_path",
      "extensions": $extensions,
      "tag": "$tag",
      "enabled": true
    }
  ]
}
EOF
    
    log "INFO" "Generated local-only configuration at $CONFIG_PATH"
}

# API installation setup
install_api_setup() {
    echo
    echo "Deep Thought Trillian - API Upload Setup"
    echo "======================================="
    echo
    
    # Get API endpoint
    printf "API endpoint URL? [https://api.deep-thought.cloud/api/v1/transcribe]: "
    read -r api_endpoint
    api_endpoint="${api_endpoint:-https://api.deep-thought.cloud/api/v1/transcribe}"
    
    # Get credentials
    printf "Username: "
    read -r api_username
    
    printf "Password: "
    read -rs api_password
    echo
    
    # Test API connection
    echo "Testing API connection..."
    if test_api_connection "$api_endpoint" "$api_username" "$api_password"; then
        echo "✓ API connection test successful"
    else
        echo "⚠ API connection test failed (will proceed anyway)"
    fi
    echo
    
    # Folder selection with suggestions
    echo "Folder to monitor?"
    echo "  Common options:"
    echo "  1. ~/Downloads (browser downloads)"
    
    # Add Voice Memos option on macOS
    local voice_memos_option=""
    if detect_voice_memos >/dev/null 2>&1; then
        voice_memos_option=$(detect_voice_memos)
        echo "  2. $voice_memos_option ⭐"
        echo "  3. ~/Desktop (desktop files)"
        echo "  4. ~/Documents (document folder)"
        echo "  5. Custom path"
    else
        echo "  2. ~/Desktop (desktop files)"
        echo "  3. ~/Documents (document folder)"
        echo "  4. Custom path"
    fi
    
    printf "  Choose [1]: "
    read -r folder_choice
    folder_choice="${folder_choice:-1}"
    
    local source_path
    local tag="upload"
    local use_cron=false
    
    case "$folder_choice" in
        1) source_path="~/Downloads" ;;
        2) 
            if [[ -n "$voice_memos_option" ]]; then
                source_path="~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
                tag="voice"
                use_cron=true
                echo "✓ Selected Voice Memos folder"
                echo "⚠ Voice Memos requires special permissions on macOS"
                echo "✓ Will use cron installation method for Voice Memos access"
            else
                source_path="~/Desktop"
            fi
            ;;
        3)
            if [[ -n "$voice_memos_option" ]]; then
                source_path="~/Desktop"
            else
                source_path="~/Documents"
            fi
            ;;
        4)
            if [[ -n "$voice_memos_option" ]]; then
                source_path="~/Documents"
            else
                printf "Enter custom path: "
                read -r source_path
            fi
            ;;
        5)
            echo "Custom path options:"
            echo "  a. Enter your own path"
            echo "  b. Create folder under ~/Documents/deep-thought-trillian/"
            printf "Choose [a]: "
            read -r custom_choice
            custom_choice="${custom_choice:-a}"
            
            if [[ "$custom_choice" == "b" ]]; then
                printf "Folder name under ~/Documents/deep-thought-trillian/: "
                read -r folder_name
                if [[ -n "$folder_name" ]]; then
                    source_path="~/Documents/deep-thought-trillian/$folder_name"
                    # Create the directory
                    mkdir -p "${source_path/#\~/$HOME}"
                    echo "✓ Created directory: $source_path"
                else
                    source_path="~/Downloads"
                fi
            else
                printf "Enter custom path: "
                read -r source_path
            fi
            ;;
        *) source_path="~/Downloads" ;;
    esac
    
    # Expand ~ in source path
    source_path_expanded="${source_path/#\~/$HOME}"
    
    # Validate source directory
    if [[ ! -d "$source_path_expanded" ]]; then
        echo "⚠ Directory doesn't exist: $source_path_expanded"
        echo "This may cause issues during monitoring."
    else
        local file_count=$(find "$source_path_expanded" -maxdepth 1 -type f \( -name "*.pdf" -o -name "*.jpg" -o -name "*.png" -o -name "*.doc" -o -name "*.docx" -o -name "*.m4a" -o -name "*.wav" \) 2>/dev/null | wc -l | tr -d ' ')
        echo "✓ Found $file_count existing files in folder"
        echo "ℹ️  IMPORTANT: Only NEW files added after installation will be uploaded"
        echo "ℹ️  Existing $file_count files will NOT be uploaded (prevents duplicates)"
    fi
    
    # Generate configuration
    generate_api_config "$api_endpoint" "$api_username" "$api_password" "$source_path" "$tag"
    
    # Install service (use cron for Voice Memos)
    if [[ "$use_cron" == "true" ]]; then
        echo "Installing with cron method for Voice Memos..."
        install_cron_service_minimal
    else
        echo "Installing service..."
        check_dependencies
        install_service
    fi
    
    echo
    echo "✓ API Upload Setup Complete!"
    echo "✓ Monitoring: $source_path"
    echo "✓ Uploading to: $api_endpoint"
    echo "✓ Service installed and running"
    echo
    echo "Check status: $0 --status"
    echo "View logs: tail -f $LOG_FILE"
}

# Local installation setup
install_local_setup() {
    echo
    echo "Deep Thought Trillian - Local Organization Setup"
    echo "==============================================="
    echo
    
    # Source folder selection
    echo "Source folder to monitor?"
    echo "  Common options:"
    echo "  1. ~/Downloads (browser downloads)"
    echo "  2. ~/Desktop (desktop files)"
    echo "  3. ~/Documents (document folder)"
    echo "  4. Custom path"
    printf "  Choose [1]: "
    read -r source_choice
    source_choice="${source_choice:-1}"
    
    local source_path
    case "$source_choice" in
        1) source_path="~/Downloads" ;;
        2) source_path="~/Desktop" ;;
        3) source_path="~/Documents" ;;
        4) 
            printf "Enter custom path: "
            read -r source_path
            ;;
        *) source_path="~/Downloads" ;;
    esac
    
    # Destination folder selection
    echo
    echo "Destination folder for organized files?"
    echo "  Suggested options:"
    echo "  1. ~/Documents/organized-files"
    echo "  2. ~/Dropbox/organized-files"
    echo "  3. ~/Google Drive/organized-files"
    echo "  4. Custom path"
    printf "  Choose [1]: "
    read -r dest_choice
    dest_choice="${dest_choice:-1}"
    
    local dest_path
    case "$dest_choice" in
        1) dest_path="~/Documents/organized-files" ;;
        2) dest_path="~/Dropbox/organized-files" ;;
        3) dest_path="~/Google Drive/organized-files" ;;
        4) 
            printf "Enter custom path: "
            read -r dest_path
            ;;
        *) dest_path="~/Documents/organized-files" ;;
    esac
    
    # File types
    printf "File types to monitor? [pdf,m4a,wav]: "
    read -r file_types
    file_types="${file_types:-pdf,m4a,wav}"
    
    # Convert to JSON array
    local extensions_json
    extensions_json=$(echo "$file_types" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    
    # Expand paths
    local source_path_expanded="${source_path/#\~/$HOME}"
    local dest_path_expanded="${dest_path/#\~/$HOME}"
    
    # Validate and create directories
    if [[ ! -d "$source_path_expanded" ]]; then
        echo "⚠ Source directory doesn't exist: $source_path_expanded"
    else
        echo "✓ Source directory exists and is accessible"
    fi
    
    if [[ ! -d "$dest_path_expanded" ]]; then
        echo "Creating destination directory: $dest_path_expanded"
        if mkdir -p "$dest_path_expanded"; then
            echo "✓ Destination directory created"
        else
            echo "✗ Failed to create destination directory"
            exit 1
        fi
    else
        echo "✓ Destination directory exists"
    fi
    
    # Generate configuration
    generate_local_config "$source_path" "$dest_path" "$extensions_json" "local"
    
    # Install service
    echo "Installing service..."
    check_dependencies
    install_service
    
    echo
    echo "✓ Local Organization Setup Complete!"
    echo "✓ Monitoring: $source_path"
    echo "✓ Organizing to: $dest_path"
    echo "✓ File types: $file_types"
    echo "✓ Service installed and running"
    echo
    echo "Check status: $0 --status"
    echo "View logs: tail -f $LOG_FILE"
}

# Minimal cron installation for API setup
install_cron_service_minimal() {
    log "INFO" "Installing cron-based monitoring for Voice Memos..."
    
    # Check dependencies
    check_dependencies
    
    # Create cron wrapper script
    create_cron_wrapper
    
    # Install cron job
    install_cron_job
    
    # Initialize status file
    echo "status=installed" > "$CRON_STATUS"
    echo "last_check=$(date +%s)" >> "$CRON_STATUS"
    echo "install_time=$(date)" >> "$CRON_STATUS"
    
    log "INFO" "Cron-based monitoring installed successfully"
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
    
    # Get API configuration
    get_api_config
    
    local copy_success=true
    local upload_success=true
    local basename
    basename=$(basename "$file")
    
    # Handle different upload modes
    case "${API_UPLOAD_MODE:-copy_and_upload}" in
        "copy_only")
            # Original behavior - only copy locally
            copy_success=$(copy_file_locally "$file" "$tag" "$destination")
            ;;
        "upload_only")
            # Only upload to API
            if [[ "${API_UPLOAD_ENABLED:-false}" == "true" ]]; then
                if upload_file_to_api "$file" "$tag" "$API_ENDPOINT" "$API_USERNAME" "$API_PASSWORD" "$API_TIMEOUT"; then
                    log "INFO" "API upload successful: $basename"
                    upload_success=true
                else
                    log "ERROR" "API upload failed: $basename"
                    upload_success=false
                fi
            else
                log "WARN" "Upload mode is 'upload_only' but API upload is not enabled"
                return 1
            fi
            ;;
        "copy_and_upload")
            # Both copy locally and upload to API
            copy_success=$(copy_file_locally "$file" "$tag" "$destination")
            
            if [[ "${API_UPLOAD_ENABLED:-false}" == "true" ]]; then
                if upload_file_to_api "$file" "$tag" "$API_ENDPOINT" "$API_USERNAME" "$API_PASSWORD" "$API_TIMEOUT"; then
                    log "INFO" "API upload successful: $basename"
                    upload_success=true
                else
                    log "WARN" "API upload failed: $basename (local copy still successful)"
                    upload_success=false
                fi
            fi
            ;;
        *)
            log "ERROR" "Unknown upload mode: ${API_UPLOAD_MODE:-copy_and_upload}"
            return 1
            ;;
    esac
    
    # Update processed database if at least one operation succeeded
    if [[ "$copy_success" == "true" || "$upload_success" == "true" ]]; then
        mkdir -p "$(dirname "$PROCESSED_DB")"
        if [[ -f "$PROCESSED_DB" ]]; then
            sed -i.bak "/^$(echo "$file" | sed 's/[[\.*^$()+?{|]/\\&/g'):/d" "$PROCESSED_DB" 2>/dev/null || true
        fi
        echo "$file_entry" >> "$PROCESSED_DB"
        return 0
    else
        log "ERROR" "All operations failed for file: $basename"
        return 1
    fi
}

# Copy file locally (original functionality)
copy_file_locally() {
    local file="$1"
    local tag="$2"
    local destination="$3"
    
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
        echo "true"
        return 0
    else
        log "ERROR" "Failed to copy: $file"
        echo "false"
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
    echo "Or with API upload:"
    echo "  $0 --monitor --api-upload --api-endpoint http://server:8080/api/v1/transcribe --api-username user --api-password pass"
}

# Monitor with manual arguments (no config files required)
monitor_manual() {
    local source_dir="${DTT_SOURCE_DIR:-}"
    local dest_dir="${DTT_DEST_DIR:-}"
    local file_tag="${DTT_FILE_TAG:-manual}"
    local extensions="${DTT_EXTENSIONS:-pdf,jpg,png,doc,docx,mp3,m4a}"
    local poll_interval="${DTT_POLL_INTERVAL:-5}"
    
    # Get API configuration first
    get_api_config
    
    # Auto-enable API upload if upload_only mode is specified
    if [[ "${API_UPLOAD_MODE:-copy_and_upload}" == "upload_only" ]]; then
        export API_UPLOAD_ENABLED="true"
        export DTT_API_UPLOAD_ENABLED="true"
    fi
    
    if [[ -z "$source_dir" ]]; then
        log "ERROR" "Manual mode requires source directory"
        echo "Usage: $0 --monitor --source <dir> [--dest <dir>] [--tag <tag>] [--ext <extensions>]"
        echo "Or set environment variables: DTT_SOURCE_DIR, DTT_DEST_DIR"
        echo "API upload options: --api-upload --api-endpoint <url> --api-username <user> --api-password <pass>"
        exit 1
    fi
    
    # Check destination requirement based on upload mode
    if [[ "${API_UPLOAD_MODE:-copy_and_upload}" != "upload_only" && -z "$dest_dir" ]]; then
        log "ERROR" "Destination directory required for copy_only and copy_and_upload modes"
        echo "Usage: $0 --monitor --source <dir> --dest <dir> [--tag <tag>] [--ext <extensions>]"
        echo "Or use --upload-mode upload_only to skip local copying"
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
    
    # Create destination directory if it doesn't exist (only for modes that need it)
    if [[ "${API_UPLOAD_MODE:-copy_and_upload}" != "upload_only" && ! -d "$dest_dir" ]]; then
        if [[ "${DTT_AUTO_CREATE_DIRS:-true}" == "true" ]]; then
            mkdir -p "$dest_dir"
            log "INFO" "Created destination directory: $dest_dir"
        else
            log "ERROR" "Destination directory does not exist: $dest_dir"
            exit 1
        fi
    fi
    
    # Get API configuration
    get_api_config
    
    log "INFO" "Starting Deep Thought Trillian v$VERSION (Manual Mode)"
    log "INFO" "Source: $source_dir"
    log "INFO" "Destination: $dest_dir"
    log "INFO" "Tag: $file_tag"
    log "INFO" "Extensions: $extensions"
    log "INFO" "Poll interval: ${poll_interval}s"
    
    if [[ "${API_UPLOAD_ENABLED:-false}" == "true" ]]; then
        log "INFO" "API Upload: Enabled"
        log "INFO" "API Endpoint: ${API_ENDPOINT:-https://api.deep-thought.cloud/api/v1/transcribe}"
        log "INFO" "API Username: ${API_USERNAME:-not set}"
        log "INFO" "Upload Mode: ${API_UPLOAD_MODE:-copy_and_upload}"
    else
        log "INFO" "API Upload: Disabled"
    fi
    
    # Convert extensions to array
    IFS=',' read -ra ext_array <<< "$extensions"
    
    # Store PID
    echo $$ > "$PID_FILE"
    
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
    
    # Check if we have manual mode parameters (source dir is required, dest dir depends on upload mode)
    if [[ -n "${DTT_SOURCE_DIR:-}" ]]; then
        monitor_manual
        return
    fi
    
    # Load environment variables
    load_env
    
    # Check again after loading .env
    if [[ -n "${DTT_SOURCE_DIR:-}" ]]; then
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
    
    # Get API configuration
    get_api_config
    
    log "INFO" "Starting Deep Thought Trillian v$VERSION"
    log "INFO" "Destination: $destination"
    log "INFO" "OS: $OS_TYPE"
    
    if [[ "${API_UPLOAD_ENABLED:-false}" == "true" ]]; then
        log "INFO" "API Upload: Enabled"
        log "INFO" "API Endpoint: ${API_ENDPOINT:-https://api.deep-thought.cloud/api/v1/transcribe}"
        log "INFO" "API Username: ${API_USERNAME:-not set}"
        log "INFO" "Upload Mode: ${API_UPLOAD_MODE:-copy_and_upload}"
    else
        log "INFO" "API Upload: Disabled"
    fi
    
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
    echo "[OK] API upload functionality available"
    echo
    echo "Next steps:"
    echo "1. Edit configuration: $CONFIG_PATH"
    echo "2. Enable directories you want to monitor"
    echo "3. Configure API upload if desired"
    echo "4. Check status: $0 --status-cron"
    echo "5. View logs: tail -f $LOG_FILE"
    echo "6. View cron logs: tail -f $CRON_LOG"
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
    
    # Show API configuration
    local api_enabled
    api_enabled=$(jq -r '.api_upload.enabled // false' "$CONFIG_PATH" 2>/dev/null)
    if [[ "$api_enabled" == "true" ]]; then
        local api_endpoint api_username api_mode
        api_endpoint=$(jq -r '.api_upload.endpoint // "not set"' "$CONFIG_PATH" 2>/dev/null)
        api_username=$(jq -r '.api_upload.username // "not set"' "$CONFIG_PATH" 2>/dev/null)
        api_mode=$(jq -r '.api_upload.upload_mode // "copy_and_upload"' "$CONFIG_PATH" 2>/dev/null)
        echo "  API Upload: Enabled"
        echo "  API Endpoint: $api_endpoint"
        echo "  API Username: $api_username"
        echo "  Upload Mode: $api_mode"
    else
        echo "  API Upload: Disabled"
    fi
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
    
    # Show API configuration
    local api_enabled
    api_enabled=$(jq -r '.api_upload.enabled // false' "$CONFIG_PATH" 2>/dev/null)
    if [[ "$api_enabled" == "true" ]]; then
        local api_endpoint api_username api_mode
        api_endpoint=$(jq -r '.api_upload.endpoint // "not set"' "$CONFIG_PATH" 2>/dev/null)
        api_username=$(jq -r '.api_upload.username // "not set"' "$CONFIG_PATH" 2>/dev/null)
        api_mode=$(jq -r '.api_upload.upload_mode // "copy_and_upload"' "$CONFIG_PATH" 2>/dev/null)
        echo "  API Upload: Enabled"
        echo "  API Endpoint: $api_endpoint"
        echo "  API Username: $api_username"
        echo "  Upload Mode: $api_mode"
    else
        echo "  API Upload: Disabled"
    fi
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
            echo "- Check status with: systemctl --
user status deep-thought-trillian"
            echo
            ;;
    esac
    echo "Configuration: $CONFIG_PATH"
    echo "Logs: $LOG_FILE"
    echo
    echo "Next steps:"
    echo "1. Edit configuration: $CONFIG_PATH"
    echo "2. Enable directories you want to monitor"
    echo "3. Configure API upload if desired"
    echo "4. Check status: $0 --status"
    echo "5. View logs: tail -f $LOG_FILE"
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

# Upload file to Deep Thought API
upload_to_api() {
    local file_path="$1"
    local tag="$2"
    local api_url="${DTT_API_URL:-http://155.4.75.114:8080}"
    local username="${DTT_API_USERNAME:-}"
    local password="${DTT_API_PASSWORD:-}"
    
    # Validate required parameters
    if [[ -z "$file_path" ]]; then
        log "ERROR" "File path is required for upload"
        return 1
    fi
    
    if [[ ! -f "$file_path" ]]; then
        log "ERROR" "File does not exist: $file_path"
        return 1
    fi
    
    if [[ -z "$username" || -z "$password" ]]; then
        log "ERROR" "API credentials required. Set DTT_API_USERNAME and DTT_API_PASSWORD"
        return 1
    fi
    
    log "INFO" "Uploading file to Deep Thought API: $(basename "$file_path")"
    log "INFO" "API URL: $api_url"
    log "INFO" "Username: $username"
    
    # Prepare upload parameters
    local upload_params=(
        -X POST
        -u "$username:$password"
        -F "file=@$file_path"
        -F "language=auto"
        -F "use_kb_whisper=true"
        -F "priority=normal"
    )
    
    # Add tag to filename if provided
    if [[ -n "$tag" ]]; then
        local basename=$(basename "$file_path")
        local name="${basename%.*}"
        local ext="${basename##*.}"
        local tagged_name="[${tag}]_${name}.${ext}"
        upload_params+=(-F "original_filename=$tagged_name")
        log "INFO" "Tagged filename: $tagged_name"
    fi
    
    # Perform upload
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" "${upload_params[@]}" "$api_url/api/v1/transcribe")
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    log "INFO" "HTTP Response Code: $http_code"
    log "INFO" "Response Body: $response_body"
    
    if [[ "$http_code" =~ ^(200|202)$ ]]; then
        log "INFO" "Upload successful"
        
        # Parse response for task_id or cache_key
        if command -v jq >/dev/null 2>&1; then
            local task_id=$(echo "$response_body" | jq -r '.task_id // empty')
            local cache_key=$(echo "$response_body" | jq -r '.result.cache_key // empty')
            local status=$(echo "$response_body" | jq -r '.status // empty')
            
            if [[ -n "$task_id" ]]; then
                log "INFO" "Task ID: $task_id"
            fi
            
            if [[ -n "$cache_key" ]]; then
                log "INFO" "Cache Key: $cache_key"
            fi
            
            if [[ "$status" == "completed" ]]; then
                log "INFO" "File was already cached - transcription available immediately"
            elif [[ "$status" == "queued" ]]; then
                log "INFO" "File queued for transcription"
            fi
        fi
        
        return 0
    else
        log "ERROR" "Upload failed with HTTP code: $http_code"
        log "ERROR" "Response: $response_body"
        return 1
    fi
}

# Show help
show_help() {
    cat << EOF
Deep Thought Trillian v$VERSION - Automatic File Organization with API Upload

USAGE:
    $0 [COMMAND]

INSTALLATION COMMANDS:
    --install           Complete installation (dependencies, config, LaunchAgent/systemd)
    --install-api       Quick API upload setup (30 seconds)
    --install-local     Quick local organization setup (30 seconds)
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

API UPLOAD OPTIONS:
    --api-endpoint <url>    API endpoint URL
    --api-username <user>   API username
    --api-password <pass>   API password
    --upload-mode <mode>    Upload mode: copy_only, upload_only, copy_and_upload
    --api-upload            Enable API upload (shorthand)

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

UPLOAD MODES:
    copy_only           Only copy files locally (original behavior)
    upload_only         Only upload to API, no local copy
    copy_and_upload     Both copy locally and upload to API (default)

EXAMPLES:
    $0 --install            # Standard installation
    $0 --install-cron       # Cron installation (for Voice Memos)
    $0 --configure          # Set up configuration
    $0 --setup              # Create config files only
    $0 --monitor            # Run with config files
    
    # Manual monitoring with local copy only
    $0 --monitor --source ~/Downloads --dest ~/organized --tag download --ext pdf,jpg
    
    # Manual monitoring with API upload only
    $0 --monitor --source ~/Downloads --upload-mode upload_only \\
       --api-endpoint http://server:8080/api/v1/transcribe \\
       --api-username myuser --api-password mypass --tag download --ext pdf,jpg
    
    # Manual monitoring with both local copy and API upload
    $0 --monitor --source ~/Downloads --dest ~/organized \\
       --api-upload --api-endpoint http://server:8080/api/v1/transcribe \\
       --api-username myuser --api-password mypass --tag download --ext pdf,jpg
    
    # Using environment variables
    DTT_SOURCE_DIR=~/Downloads DTT_DEST_DIR=~/organized \\
    DTT_API_UPLOAD_ENABLED=true DTT_API_ENDPOINT=http://server:8080/api/v1/transcribe \\
    DTT_API_USERNAME=myuser DTT_API_PASSWORD=mypass $0 --monitor
    
    $0 --status             # Check standard service status
    $0 --status-cron        # Check cron service status

FILES:
    Config:      $CONFIG_PATH
    Log:         $LOG_FILE
    Cron Log:    $CRON_LOG
    PID:         $PID_FILE

API AUTHENTICATION:
    The script uses HTTP Basic Authentication to upload files to the Deep Thought API.
    Configure credentials via:
    - Command line: --api-username <user> --api-password <pass>
    - Environment: DTT_API_USERNAME=<user> DTT_API_PASSWORD=<pass>
    - Config file: Edit api_upload section in $CONFIG_PATH

For more information, see the README.md file.
EOF
}

# Main execution
main() {
    case "${1:-}" in
        --install)
            install_complete
            ;;
        --install-api)
            install_api_setup
            ;;
        --install-local)
            install_local_setup
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
            shift
            start_monitoring "$@"
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
