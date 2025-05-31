# Deep Thought Trillian v1.1.1

A cross-platform file monitoring and organization system that automatically copies files from specified directories to a centralized destination with intelligent tagging and naming, plus HTTP API upload support for server integration.

## Features

- **Real-time monitoring** using `fswatch` (macOS) or `inotify` (Linux)
- **Smart organization** with customizable tags and file naming
- **HTTP API upload** with Basic Authentication to Deep Thought server
- **Flexible upload modes** (copy only, upload only, or both)
- **Dual installation modes** (LaunchAgent/systemd + Cron/Screen)
- **Flexible configuration** supporting any file types and directories
- **Duplicate protection** with timestamp-based versioning
- **Voice Memos support** with cron-based bypass for macOS restrictions
- **Environment variable configuration** (.env support)

## Quick Start (30 seconds)

### API Upload Setup
```bash
curl -O https://raw.githubusercontent.com/tandregbg/deep-thought-trillian/main/deep-thought-trillian.sh
chmod +x deep-thought-trillian.sh
./deep-thought-trillian.sh --install-api
```
Enter: API endpoint, username, password, folder to monitor  
Done! Files are now uploaded automatically.

### Local File Organization
```bash
./deep-thought-trillian.sh --install-local
```
Enter: source folder, destination folder, file types  
Done! Files are now organized locally.

## Advanced Installation

### Standard Installation (Full Configuration)
```bash
./deep-thought-trillian.sh --install
```

### Cron Installation (For Voice Memos & Restricted Directories)
```bash
./deep-thought-trillian.sh --install-cron
```

**Use cron installation when:**
- Monitoring Voice Memos on macOS
- LaunchAgent has permission restrictions
- Need to bypass macOS security limitations

## Configuration

### JSON Configuration
Configuration is stored in `~/.deep-thought-trillian/config.json`:

```json
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
      "enabled": true
    },
    {
      "name": "downloads",
      "path": "~/Downloads",
      "extensions": ["pdf", "jpg", "png", "mp4"],
      "tag": "download",
      "enabled": true
    }
  ]
}
```

### Environment Variables (.env)
Create `~/.deep-thought-trillian/.env` for environment-specific settings:

```bash
# Core functionality
DTT_SOURCE_DIR=~/Downloads
DTT_DEST_DIR=~/Documents/organized-files
DTT_FILE_TAG=download
DTT_EXTENSIONS=pdf,jpg,png,mp4

# Behavior settings
DTT_LOG_LEVEL=INFO
DTT_POLL_INTERVAL=5
DTT_REAL_TIME=true

# Feature flags
DTT_VOICE_MEMOS=true
DTT_AUTO_CREATE_DIRS=true

# API Upload Configuration
DTT_API_UPLOAD_ENABLED=false
DTT_API_ENDPOINT=https://api.deep-thought.cloud/api/v1/transcribe
DTT_API_USERNAME=
DTT_API_PASSWORD=
DTT_API_UPLOAD_MODE=copy_and_upload
DTT_API_TIMEOUT=30
```

### Configuration Fields

| Field | Description | Example |
|-------|-------------|---------|
| `destination` | Where organized files are copied | `"~/Dropbox/organized"` |
| `path` | Directory to monitor | `"~/Downloads"` |
| `extensions` | File extensions to monitor (without dots) | `["pdf", "jpg"]` |
| `tag` | Prefix tag for copied files | `"download"` |
| `enabled` | Whether to monitor this directory | `true`/`false` |
| `api_upload.enabled` | Enable HTTP API upload | `true`/`false` |
| `api_upload.endpoint` | API endpoint URL | `"http://server:8080/api/v1/transcribe"` |
| `api_upload.username` | API username for Basic Auth | `"myuser"` |
| `api_upload.password` | API password for Basic Auth | `"mypass"` |
| `api_upload.upload_mode` | Upload behavior | `"copy_only"`, `"upload_only"`, `"copy_and_upload"` |
| `api_upload.timeout` | API request timeout (seconds) | `30` |

## Commands

### Installation & Configuration
```bash
./deep-thought-trillian.sh --install           # Standard installation
./deep-thought-trillian.sh --install-cron      # Cron installation (Voice Memos)
./deep-thought-trillian.sh --configure         # Interactive configuration
```

### Standard Service Management
```bash
./deep-thought-trillian.sh --status            # Show status
./deep-thought-trillian.sh --start             # Start service
./deep-thought-trillian.sh --stop              # Stop service
./deep-thought-trillian.sh --uninstall         # Remove service
```

### Cron Service Management
```bash
./deep-thought-trillian.sh --status-cron       # Show cron status
./deep-thought-trillian.sh --start-cron        # Start screen session
./deep-thought-trillian.sh --stop-cron         # Stop screen session
./deep-thought-trillian.sh --uninstall-cron    # Remove cron installation
```

### Manual Execution (No Installation Required)
```bash
# Setup config files only (no service installation)
./deep-thought-trillian.sh --setup

# Run with command-line arguments (local copy only)
./deep-thought-trillian.sh --monitor --source ~/Downloads --dest ~/organized --tag download --ext pdf,jpg,png

# Run with API upload only (no local copy)
./deep-thought-trillian.sh --monitor --source ~/Downloads --upload-mode upload_only \
  --api-endpoint http://server:8080/api/v1/transcribe \
  --api-username myuser --api-password mypass --tag download --ext pdf,jpg,png

# Example with specific IP address and custom tag
./deep-thought-trillian.sh --monitor \
  --source test/ \
  --upload-mode upload_only \
  --api-endpoint http://192.168.11.125:8080/api/v1/transcribe \
  --api-username test \
  --api-password test123 \
  --tag current-folder

# Run with both local copy and API upload
./deep-thought-trillian.sh --monitor --source ~/Downloads --dest ~/organized \
  --api-upload --api-endpoint http://server:8080/api/v1/transcribe \
  --api-username myuser --api-password mypass --tag download --ext pdf,jpg,png

# Run with environment variables
DTT_SOURCE_DIR=~/Downloads DTT_DEST_DIR=~/organized ./deep-thought-trillian.sh --monitor

# Run with .env file configuration
./deep-thought-trillian.sh --monitor
```

### Testing & Debugging
```bash
./deep-thought-trillian.sh --monitor           # Run in foreground
tail -f ~/.deep-thought-trillian/deep-thought-trillian.log  # View logs
```

## macOS Permissions

### Required Permissions
1. **System Preferences** > **Security & Privacy** > **Privacy**
2. **Full Disk Access** - Add Terminal app
3. **Files and Folders** - Grant access to directories you want to monitor

### Voice Memos Access
Voice Memos requires special handling due to macOS security restrictions:

**LaunchAgent limitations:**
- May get "Operation not permitted" errors
- Service might restart repeatedly

**Solution: Use Cron Installation**
```bash
./deep-thought-trillian.sh --uninstall      # Remove standard service
./deep-thought-trillian.sh --install-cron   # Install cron version
```

## HTTP API Upload

### Overview
Deep Thought Trillian v1.1.0 introduces HTTP API upload functionality, allowing files to be automatically uploaded to a Deep Thought server for processing (e.g., transcription, analysis).

### Upload Modes
- **`copy_only`** - Only copy files locally (original behavior)
- **`upload_only`** - Only upload to API, no local copy
- **`copy_and_upload`** - Both copy locally and upload to API (default)

### Authentication
Uses HTTP Basic Authentication with username and password.

### API Response
The API should return JSON with optional `task_id` or `id` field for tracking:
```json
{
  "task_id": "abc123",
  "status": "queued",
  "message": "File uploaded successfully"
}
```

### Configuration Examples

**Via JSON config:**
```json
{
  "api_upload": {
    "enabled": true,
    "endpoint": "https://deepthought.example.com/api/v1/transcribe",
    "username": "myuser",
    "password": "mypass",
    "upload_mode": "copy_and_upload",
    "timeout": 30
  }
}
```

**Via environment variables:**
```bash
DTT_API_UPLOAD_ENABLED=true
DTT_API_ENDPOINT=https://deepthought.example.com/api/v1/transcribe
DTT_API_USERNAME=myuser
DTT_API_PASSWORD=mypass
DTT_API_UPLOAD_MODE=copy_and_upload
```

**Via command line:**
```bash
./deep-thought-trillian.sh --monitor --source ~/Downloads \
  --api-upload --api-endpoint https://deepthought.example.com/api/v1/transcribe \
  --api-username myuser --api-password mypass
```

## File Organization

Files are copied with the naming pattern: `[tag]_originalfilename.ext`

**Examples:**
- `invoice.pdf` > `[download]_invoice.pdf`
- `recording.m4a` > `[voice]_recording.m4a`
- `scan.pdf` > `[scan]_scan.pdf`

**Duplicate handling:** Modified files get timestamps: `[tag]_filename_20241124_143022.ext`

## Troubleshooting

### Common Issues

**"Operation not permitted" (macOS):**
- Grant Full Disk Access to Terminal
- For Voice Memos, use `--install-cron`

**Missing dependencies:**
```bash
# macOS
brew install jq fswatch

# Ubuntu/Debian
sudo apt-get install jq inotify-tools

# CentOS/RHEL
sudo yum install jq inotify-tools
```

**Service not starting:**
1. Check status: `./deep-thought-trillian.sh --status`
2. Test manually: `./deep-thought-trillian.sh --monitor`
3. Check logs: `tail -f ~/.deep-thought-trillian/deep-thought-trillian.log`

**API Upload Issues:**
- Check API endpoint URL and credentials
- Verify server is accessible: `curl -u username:password http://server:8080/api/v1/transcribe`
- Check timeout settings if uploads are slow
- Review logs for HTTP error codes

### Log Analysis
```bash
# View logs
tail -f ~/.deep-thought-trillian/deep-thought-trillian.log

# Cron logs (if using cron installation)
tail -f ~/.deep-thought-trillian/cron-monitor.log

# Search for errors
grep ERROR ~/.deep-thought-trillian/deep-thought-trillian.log

# Search for API upload activity
grep "API upload" ~/.deep-thought-trillian/deep-thought-trillian.log

# Search for upload failures
grep "Upload failed" ~/.deep-thought-trillian/deep-thought-trillian.log
```

## Installation Methods Comparison

| Feature | Standard Installation | Cron Installation |
|---------|----------------------|-------------------|
| **Method** | LaunchAgent/systemd | Cron + Screen |
| **Voice Memos** | Limited (macOS restrictions) | Full access |
| **Auto-start** | On login | Every minute check |
| **Performance** | Optimal | Slightly higher overhead |
| **Use Case** | General directories | Restricted directories |

## Requirements

**macOS:**
- Homebrew (for dependencies)
- Full Disk Access permissions

**Linux:**
- Package manager (`apt-get` or `yum`)
- sudo access for dependencies

**Dependencies (auto-installed):**
- `jq` - JSON processor
- `fswatch` (macOS) or `inotify-tools` (Linux)
- `screen` (for cron installation)
- `curl` - HTTP client (for API uploads)

## Uninstallation

```bash
# Standard installation
./deep-thought-trillian.sh --uninstall

# Cron installation
./deep-thought-trillian.sh --uninstall-cron

# Complete removal (both methods)
rm -rf ~/.deep-thought-trillian
rm deep-thought-trillian.sh
```

## Functional Specification

### Core Architecture

**Deep Thought Trillian** is designed as a cross-platform file monitoring and organization system with the following architectural principles:

#### 1. Monitoring Engine
- **Real-time monitoring**: Uses platform-native file system events (`fswatch` on macOS, `inotify` on Linux)
- **Polling fallback**: 5-second interval polling when real-time monitoring unavailable
- **Multi-directory support**: Simultaneous monitoring of multiple directories with different configurations

#### 2. Service Management
- **Dual deployment modes**: 
  - Standard: LaunchAgent (macOS) / systemd (Linux) for optimal integration
  - Cron: Background screen sessions for restricted environments
- **Automatic dependency management**: Installs required tools (`jq`, `fswatch`, `inotify-tools`)
- **Cross-platform compatibility**: Unified interface across macOS and Linux

#### 3. File Processing Pipeline
- **Extension filtering**: Configurable file type monitoring per directory
- **Duplicate detection**: Modification time tracking prevents reprocessing
- **Intelligent naming**: Tag-based organization with timestamp versioning
- **Atomic operations**: Safe file copying with error handling

#### 4. Configuration Management
- **JSON-based configuration**: Structured, human-readable settings
- **Environment variable overrides**: `.env` file support for deployment flexibility
- **Interactive setup**: Guided configuration wizard
- **Runtime validation**: Configuration integrity checks

#### 5. Security & Permissions
- **macOS security bypass**: Cron-based installation circumvents LaunchAgent restrictions
- **Voice Memos support**: Special handling for restricted Apple directories
- **Permission validation**: Automatic detection and guidance for required permissions

### Historical Development

This system evolved from a simple file organization script into a comprehensive monitoring solution:

**Original Concept (transcraib-agent):**
- Basic file copying with manual triggers
- Single directory monitoring
- Simple shell script implementation

**Evolution to Deep Thought Trillian v1.0.0:**
- Multi-directory real-time monitoring
- Cross-platform service integration
- Advanced configuration management
- Robust error handling and logging
- Security-aware deployment options

**Deep Thought Trillian v1.1.0 - HTTP API Integration:**
- HTTP API upload with Basic Authentication
- Flexible upload modes (copy only, upload only, both)
- Server integration for automated processing
- Enhanced configuration options
- Improved error handling and logging

### Technical Implementation

#### File System Monitoring
```bash
# macOS: fswatch integration
fswatch -0 "${watch_paths[@]}" | while IFS= read -r -d '' file; do
    process_file "$file" "$tag" "$destination"
done

# Linux: inotify integration  
inotifywait -m -e close_write,moved_to --format '%w%f' "${watch_paths[@]}"
```

#### Service Installation
```bash
# LaunchAgent (macOS)
launchctl load ~/Library/LaunchAgents/com.deep-thought-trillian.plist

# systemd (Linux)
systemctl --user enable deep-thought-trillian.service
```

#### Cron-based Monitoring
```bash
# Cron job ensures screen session persistence
* * * * * ~/.deep-thought-trillian/cron-monitor.sh >/dev/null 2>&1
```

### Performance Characteristics

- **Memory footprint**: ~5-10MB during active monitoring
- **CPU usage**: <1% during idle, <5% during file processing bursts
- **File processing latency**: <100ms for real-time events, <5s for polling
- **Scalability**: Tested with 100+ files/minute across 10+ directories

### Future Enhancements

Planned improvements for future versions:
- Web-based configuration interface
- Cloud storage integration (Dropbox, Google Drive, iCloud)
- Advanced filtering rules (file size, age, content-based)
- Notification system integration
- Performance metrics and analytics
- Plugin architecture for custom processors

## Changelog

### v1.1.1 (2025-05-31)
**Enhanced User Experience & Quick Setup**

#### New Features
- **Quick Installation Commands**: Added `--install-api` and `--install-local` for 30-second setup
- **Smart Folder Suggestions**: Interactive prompts with common folder options (Downloads, Desktop, Documents)
- **Voice Memos Auto-Detection**: Automatically detects and suggests Voice Memos folder on macOS with file count
- **API Connection Testing**: Tests API connectivity during setup process
- **Intelligent Installation**: Automatically chooses cron method for Voice Memos to bypass macOS restrictions

#### Improvements
- **Streamlined Script**: Moved verbose documentation from script to README for better maintainability
- **Enhanced Help**: Updated help text to prominently feature new quick installation options
- **Better Validation**: Validates directories and shows file counts during setup
- **Clearer Feedback**: Provides immediate success confirmations and next steps

#### User Experience
- **30-Second Setup**: Get up and running with either API upload or local organization in under 30 seconds
- **Guided Prompts**: Clear, numbered options for folder selection
- **Voice Memos Made Easy**: Seamless setup for macOS Voice Memos with automatic permission handling
- **Immediate Functionality**: Services start automatically after installation

### v1.1.0 (2024-11-24)
**HTTP API Integration**

- Added HTTP API upload functionality with Basic Authentication
- Introduced flexible upload modes (copy_only, upload_only, copy_and_upload)
- Enhanced configuration options for API integration
- Improved error handling and logging for API operations
- Added server integration for automated file processing

### v1.0.0 (2024-10-15)
**Initial Release**

- Cross-platform file monitoring (macOS and Linux)
- Real-time file system monitoring with fswatch/inotify
- Dual installation modes (LaunchAgent/systemd and Cron/Screen)
- JSON-based configuration with environment variable support
- Voice Memos support with macOS security bypass
- Intelligent file organization with tagging and duplicate handling

---

**Deep Thought Trillian v1.1.1** - Keeping your files organized automatically with HTTP API integration!
