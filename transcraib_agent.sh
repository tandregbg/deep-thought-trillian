#!/bin/bash

# Script: transcraib_agent.sh
# Description: Advanced file monitoring and organization system
# Version: 2.0.0
# Supports: macOS and Ubuntu/Linux

set -euo pipefail

# Constants
readonly SCRIPT_NAME="transcraib_agent"
readonly VERSION="2.0.1"
readonly CONFIG_DIR="$HOME/.transcraib"
readonly CONFIG_PATH="$CONFIG_DIR/config.json"
readonly LOG_FILE="$CONFIG_DIR/transcraib_agent.log"
readonly PID_FILE="$CONFIG_DIR/transcraib_agent.pid"
readonly PROCESSED_DB="$CONFIG_DIR/processed_files"

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
        readonly SERVICE_FILE="com.transcraib.agent.plist"
        ;;
    "linux")
        readonly STAT_CMD="stat -c %Y"
        readonly WATCH_CMD="inotifywait"
        readonly SERVICE_TYPE="systemd"
        readonly SERVICE_DIR="$HOME/.config/systemd/user"
        readonly SERVICE_FILE="transcraib-agent.service"
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
    
    # Print to console with colors
    case "$level" in
        "ERROR") echo -e "${RED}$timestamp [$level] $message${NC}" >&2 ;;
        "WARN")  echo -e "${YELLOW}$timestamp [$level] $message${NC}" ;;
        "INFO")  echo -e "${GREEN}$timestamp [$level] $message${NC}" ;;
        "DEBUG") echo -e "${BLUE}$timestamp [$level] $message${NC}" ;;
        *) echo "$timestamp [$level] $message" ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for jq (JSON processor)
    if ! command_exists jq; then
        missing_deps+=("jq")
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
                        brew install "$dep"
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
    echo "   Transcraib Agent Configuration"
    echo "==================================="
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
                    echo "✓ Created directory: $dest_dir"
                    break
                else
                    echo "✗ Failed to create directory"
                fi
            fi
        else
            echo "✓ Directory exists and is accessible"
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
    echo "Step 2: Enable/Disable Watch Directories"
    echo "----------------------------------------"
    echo "Review the configuration file at: $CONFIG_PATH"
    echo "Set 'enabled': true for directories you want to monitor"
    echo
    echo "✓ Configuration wizard complete!"
    echo "✓ Edit $CONFIG_PATH to customize your setup"
    echo "✓ Run '$0 --monitor' to start monitoring"
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
    if cp "$file" "$dest_path" 2>/dev/null; then
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

# Main monitoring function
start_monitoring() {
    # Validate configuration
    if ! validate_config; then
        exit 1
    fi
    
    # Get destination from config
    local destination
    destination=$(jq -r '.destination' "$CONFIG_PATH")
    destination="${destination/#\~/$HOME}"
    
    log "INFO" "Starting Transcraib Agent v$VERSION"
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
                log "WARN" "fswatch not available, falling back to polling"
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
    <string>com.transcraib.agent</string>
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
Description=Transcraib Agent File Monitor
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

# Show current status
show_status() {
    echo "Transcraib Agent v$VERSION"
    echo "========================="
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
            ;;
        "linux")
            echo "Linux Setup:"
            echo "- Service installed and started automatically"
            echo "- Check status with: systemctl --user status transcraib-agent"
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

# Show help
show_help() {
    cat << EOF
Transcraib Agent v$VERSION - Automatic File Organization

USAGE:
    $0 [COMMAND]

COMMANDS:
    --install       Complete installation (dependencies, config, service)
    --configure     Interactive configuration wizard
    --monitor       Start monitoring (foreground)
    --status        Show current status
    --start         Start monitoring service
    --stop          Stop monitoring service  
    --restart       Restart monitoring service
    --uninstall     Remove service and stop monitoring
    --help          Show this help message

EXAMPLES:
    $0 --install        # One-command setup
    $0 --configure      # Set up configuration
    $0 --monitor        # Run in foreground (for testing)
    $0 --status         # Check current status

FILES:
    Config:  $CONFIG_PATH
    Log:     $LOG_FILE
    PID:     $PID_FILE

For more information, see the README.md file.
EOF
}

# Main execution
main() {
    case "${1:-}" in
        --install)
            install_complete
            ;;
        --configure)
            configure_interactive
            ;;
        --monitor)
            start_monitoring
            ;;
        --status)
            show_status
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
        --uninstall)
            uninstall_service
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
