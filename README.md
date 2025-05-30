# Deep Thought Trillian v1.0.0

A cross-platform file monitoring and organization system that automatically copies files from specified directories to a centralized destination with intelligent tagging and naming.

## Features

- **Real-time monitoring** using `fswatch` (macOS) or `inotify` (Linux)
- **Smart organization** with customizable tags and file naming
- **Dual installation modes** (LaunchAgent/systemd + Cron/Screen)
- **Flexible configuration** supporting any file types and directories
- **Duplicate protection** with timestamp-based versioning
- **Voice Memos support** with cron-based bypass for macOS restrictions
- **Environment variable configuration** (.env support)

## Installation

### Standard Installation (Recommended)
```bash
curl -O https://raw.githubusercontent.com/tandregbg/deep-thought-trillian/main/deep-thought-trillian.sh
chmod +x deep-thought-trillian.sh
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
```

### Configuration Fields

| Field | Description | Example |
|-------|-------------|---------|
| `destination` | Where organized files are copied | `"~/Dropbox/organized"` |
| `path` | Directory to monitor | `"~/Downloads"` |
| `extensions` | File extensions to monitor (without dots) | `["pdf", "jpg"]` |
| `tag` | Prefix tag for copied files | `"download"` |
| `enabled` | Whether to monitor this directory | `true`/`false` |

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

# Run with command-line arguments
./deep-thought-trillian.sh --monitor --source ~/Downloads --dest ~/organized --tag download --ext pdf,jpg,png

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

### Log Analysis
```bash
# View logs
tail -f ~/.deep-thought-trillian/deep-thought-trillian.log

# Cron logs (if using cron installation)
tail -f ~/.deep-thought-trillian/cron-monitor.log

# Search for errors
grep ERROR ~/.deep-thought-trillian/deep-thought-trillian.log
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

---

**Deep Thought Trillian v1.0.0** - Keeping your files organized automatically!
