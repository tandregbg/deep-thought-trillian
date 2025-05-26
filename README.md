# Transcraib Agent

A cross-platform file monitoring and organization system that automatically copies files from specified directories to a centralized destination with intelligent tagging and naming.

## Features

- **Real-time monitoring** using `fswatch` (macOS) or `inotify` (Linux)
- **Smart organization** with customizable tags and file naming
- **Dual installation modes** (LaunchAgent/systemd + Cron/Screen)
- **Flexible configuration** supporting any file types and directories
- **Duplicate protection** with timestamp-based versioning
- **Voice Memos support** with cron-based bypass for macOS restrictions

## Installation

### Standard Installation (Recommended)
```bash
curl -O https://raw.githubusercontent.com/your-repo/transcraib-agent/main/transcraib-agent.sh
chmod +x transcraib-agent.sh
./transcraib-agent.sh --install
```

### Cron Installation (For Voice Memos & Restricted Directories)
```bash
./transcraib-agent.sh --install-cron
```

**Use cron installation when:**
- Monitoring Voice Memos on macOS
- LaunchAgent has permission restrictions
- Need to bypass macOS security limitations

## Configuration

Configuration is stored in `~/.transcraib-agent/config.json`:

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
./transcraib-agent.sh --install           # Standard installation
./transcraib-agent.sh --install-cron      # Cron installation (Voice Memos)
./transcraib-agent.sh --configure         # Interactive configuration
```

### Standard Service Management
```bash
./transcraib-agent.sh --status            # Show status
./transcraib-agent.sh --start             # Start service
./transcraib-agent.sh --stop              # Stop service
./transcraib-agent.sh --uninstall         # Remove service
```

### Cron Service Management
```bash
./transcraib-agent.sh --status-cron       # Show cron status
./transcraib-agent.sh --start-cron        # Start screen session
./transcraib-agent.sh --stop-cron         # Stop screen session
./transcraib-agent.sh --uninstall-cron    # Remove cron installation
```

### Testing & Debugging
```bash
./transcraib-agent.sh --monitor           # Run in foreground
tail -f ~/.transcraib-agent/transcraib-agent.log  # View logs
```

## macOS Permissions

### Required Permissions
1. **System Preferences** → **Security & Privacy** → **Privacy**
2. **Full Disk Access** - Add Terminal app
3. **Files and Folders** - Grant access to directories you want to monitor

### Voice Memos Access
Voice Memos requires special handling due to macOS security restrictions:

**LaunchAgent limitations:**
- May get "Operation not permitted" errors
- Service might restart repeatedly

**Solution: Use Cron Installation**
```bash
./transcraib-agent.sh --uninstall      # Remove standard service
./transcraib-agent.sh --install-cron   # Install cron version
```

## File Organization

Files are copied with the naming pattern: `[tag]_originalfilename.ext`

**Examples:**
- `invoice.pdf` → `[download]_invoice.pdf`
- `recording.m4a` → `[voice]_recording.m4a`
- `scan.pdf` → `[scan]_scan.pdf`

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
1. Check status: `./transcraib-agent.sh --status`
2. Test manually: `./transcraib-agent.sh --monitor`
3. Check logs: `tail -f ~/.transcraib-agent/transcraib-agent.log`

### Log Analysis
```bash
# View logs
tail -f ~/.transcraib-agent/transcraib-agent.log

# Cron logs (if using cron installation)
tail -f ~/.transcraib-agent/cron-monitor.log

# Search for errors
grep ERROR ~/.transcraib-agent/transcraib-agent.log
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
./transcraib-agent.sh --uninstall

# Cron installation
./transcraib-agent.sh --uninstall-cron

# Complete removal (both methods)
rm -rf ~/.transcraib-agent
rm transcraib-agent.sh
```

## Version History

**v2.0.3 (2025-05-26)**
- Added cron-based installation method
- Voice Memos support with security bypass
- Enhanced status reporting for both installation methods
- Automatic Voice Memos detection and recommendations

**v2.0.2 (2025-05-25)**
- Fixed logging bugs and LaunchAgent PATH issues
- Added screen-based background monitoring documentation
- Improved Full Disk Access setup instructions

---

**Transcraib Agent** - Keeping your files organized automatically!
