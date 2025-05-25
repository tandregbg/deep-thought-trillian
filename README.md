# Transcraib Agent

A cross-platform file monitoring and organization system that automatically copies files from specified directories to a centralized destination with intelligent tagging and naming.

## Features

- 🚀 **Real-time monitoring** using `fswatch` (macOS) or `inotify` (Linux)
- 📁 **Smart organization** with customizable tags and file naming
- 🔄 **Automatic service management** (LaunchAgent/systemd)
- 🎯 **Flexible configuration** supporting any file types and directories
- 🛡️ **Duplicate protection** with timestamp-based versioning
- 🌍 **Cross-platform** support for macOS and Ubuntu/Linux
- 📱 **App integration** ready for Voice Memos, TurboScan, and other apps

## Quick Start

### One-Command Installation

```bash
# Download and install
curl -O https://raw.githubusercontent.com/your-repo/transcraib-agent/main/transcraib-agent.sh
chmod +x transcraib-agent.sh
./transcraib-agent.sh --install
```

### Manual Setup

1. **Download the script**
   ```bash
   wget https://raw.githubusercontent.com/your-repo/transcraib-agent/main/transcraib-agent.sh
   chmod +x transcraib-agent.sh
   ```

2. **Install and configure**
   ```bash
   ./transcraib-agent.sh --install
   ```

3. **Edit configuration** (optional)
   ```bash
   nano ~/.transcraib-agent/config.json
   ```

4. **Start monitoring**
   ```bash
   ./transcraib-agent.sh --status
   ```

## Installation Requirements

### macOS
- **Homebrew** (for automatic dependency installation)
- **System Permissions** (Full Disk Access + Files and Folders)

### Ubuntu/Linux
- **Package manager** (`apt-get` or `yum`)
- **sudo access** (for dependency installation)

### Dependencies (auto-installed)
- `jq` - JSON processor
- `fswatch` (macOS) or `inotify-tools` (Linux) - File system monitoring

## Configuration

The configuration is stored in `~/.transcraib-agent/config.json`:

### Basic Structure

```json
{
  "destination": "~/Dropbox/organized-files",
  "watch_directories": [
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

### Example Configurations

#### Voice Memos + Document Scanning
```json
{
  "destination": "~/Dropbox/auto-organized",
  "watch_directories": [
    {
      "name": "voice_memos",
      "path": "~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
      "extensions": ["m4a", "wav"],
      "tag": "voice",
      "enabled": true
    },
    {
      "name": "turboscan_pdfs",
      "path": "~/Library/Mobile Documents/iCloud~com~novosoft~TurboScan/Documents",
      "extensions": ["pdf"],
      "tag": "scan",
      "enabled": true
    }
  ]
}
```

#### Complete Desktop Organization
```json
{
  "destination": "~/Dropbox/organized-files",
  "watch_directories": [
    {
      "name": "downloads",
      "path": "~/Downloads",
      "extensions": ["pdf", "jpg", "png", "mp4", "mov", "doc", "docx", "zip"],
      "tag": "download",
      "enabled": true
    },
    {
      "name": "desktop",
      "path": "~/Desktop",
      "extensions": ["pdf", "jpg", "png", "doc", "docx"],
      "tag": "desktop",
      "enabled": true
    },
    {
      "name": "screenshots",
      "path": "~/Desktop",
      "extensions": ["png"],
      "tag": "screenshot",
      "enabled": true
    }
  ]
}
```

### Configuration Fields

| Field | Description | Example |
|-------|-------------|---------|
| `destination` | Where organized files are copied | `"~/Dropbox/organized"` |
| `name` | Internal identifier for the watch directory | `"downloads"` |
| `path` | Directory to monitor | `"~/Downloads"` |
| `extensions` | File extensions to monitor (without dots) | `["pdf", "jpg"]` |
| `tag` | Prefix tag for copied files | `"download"` |
| `enabled` | Whether to monitor this directory | `true`/`false` |

## Commands

### Primary Commands
```bash
./transcraib-agent.sh --install      # Complete setup
./transcraib-agent.sh --configure    # Interactive configuration
./transcraib-agent.sh --status       # Show current status
./transcraib-agent.sh --help         # Show help
```

### Service Management
```bash
./transcraib-agent.sh --start        # Start service
./transcraib-agent.sh --stop         # Stop service
./transcraib-agent.sh --restart      # Restart service
./transcraib-agent.sh --uninstall    # Remove service
```

### Testing/Debugging
```bash
./transcraib-agent.sh --monitor      # Run in foreground (for testing)
tail -f ~/.transcraib-agent/transcraib-agent.log  # View logs
```

## macOS Permissions Setup

### Required Permissions

1. **Open System Preferences**
   - Go to Security & Privacy → Privacy

2. **Full Disk Access**
   - Add your Terminal app (Terminal.app, iTerm2, etc.)
   - This allows access to app containers and system directories

3. **Files and Folders**
   - Add your Terminal app
   - Grant access to:
     - Desktop Folder
     - Documents Folder
     - Downloads Folder
     - Any other directories you want to monitor

### Adding Script to Full Disk Access

To grant the script itself Full Disk Access permissions (required for LaunchAgent to access Voice Memos):

1. **Open System Preferences** → **Security & Privacy** → **Privacy**
2. **Click "Full Disk Access"** in the left sidebar
3. **Click the lock** and enter your password
4. **Click the "+" button**
5. **Press Cmd+Shift+G** to open "Go to Folder"
6. **Navigate to your script location**, e.g., `/Users/yourusername/Projects/transcraib-agent/transcraib-agent.sh`
7. **Select the script** and click "Open"

**Alternative**: Add `/bin/bash` instead:
1. **Press Cmd+Shift+G** and type: `/bin/bash`
2. **Select bash** and click "Open"

### App-Specific Directories

Some apps store files in special locations that require Full Disk Access:

- **Voice Memos**: `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`
- **TurboScan**: `~/Library/Mobile Documents/iCloud~com~novosoft~TurboScan/Documents`
- **Other iCloud Apps**: `~/Library/Mobile Documents/iCloud~com~*`

### Voice Memos LaunchAgent Limitation

⚠️ **Important**: macOS LaunchAgents have security restrictions that can prevent access to Voice Memos, even with Full Disk Access granted.

**Symptoms:**
- `cp: Operation not permitted` errors in logs
- Service restarting repeatedly
- Files not being processed

**Solutions:**

#### Option 1: Foreground Mode (Recommended)
```bash
# Stop the background service
./transcraib-agent.sh --uninstall

# Use foreground mode when needed
./transcraib-agent.sh --monitor
```

#### Option 2: Screen Background Mode
Run monitoring in background using screen (bypasses LaunchAgent restrictions):
```bash
# Start in background with screen
screen -dmS transcraib-agent ./transcraib-agent.sh --monitor

# Check if running
screen -list

# Attach to session
screen -r transcraib-agent

# Detach from session (Ctrl+A, then D)
```

#### Option 3: Alternative Directories Only
Configure LaunchAgent to monitor only accessible directories:
- ✅ Downloads: `~/Downloads`
- ✅ Desktop: `~/Desktop`
- ✅ Documents: `~/Documents`
- ❌ Voice Memos: Use foreground/screen mode

### Permission Troubleshooting

If you get "Operation not permitted" errors:

1. **Check Terminal permissions** in System Preferences
2. **Restart Terminal** after granting permissions
3. **Test access** manually:
   ```bash
   ls "~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
   ```
4. **Re-run installation** if needed
5. **Consider screen-based background mode** for Voice Memos

## Background Mode (Alternative to LaunchAgent)

### Using Screen for Background Monitoring

For directories with access restrictions (like Voice Memos), use screen instead of LaunchAgent:

```bash
# Start monitoring in background
screen -dmS transcraib-agent ./transcraib-agent.sh --monitor

# Check if running
screen -list
# Should show: 12345.transcraib-agent

# View logs in real-time
tail -f ~/.transcraib-agent/transcraib-agent.log

# Stop monitoring
screen -S transcraib-agent -X quit
```

### Screen Session Management

```bash
# Attach to running session
screen -r transcraib-agent

# Detach from session (keep it running)
# Press Ctrl+A, then D

# Kill session
screen -S transcraib-agent -X quit

# List all screen sessions
screen -list
```

### Auto-start Screen Session

Add to your shell profile (`.bashrc`, `.zshrc`, etc.):
```bash
# Auto-start transcraib-agent if not running
if ! screen -list | grep -q "transcraib-agent"; then
    screen -dmS transcraib-agent /path/to/transcraib-agent.sh --monitor
fi
```

## File Organization

### Naming Convention

Files are copied with the following naming pattern:
```
[tag]_originalfilename.ext
```

Examples:
- `invoice.pdf` → `[download]_invoice.pdf`
- `recording.m4a` → `[voice]_recording.m4a`
- `scan.pdf` → `[scan]_scan.pdf`

### Duplicate Handling

When a file is modified, a timestamp is added:
```
[tag]_filename_20241124_143022.ext
```

This prevents overwrites and maintains file history.

### Directory Structure

All files are copied to a flat structure in the destination directory. The tag system provides organization without nested folders.

## Service Management

### macOS (LaunchAgent)

The service runs automatically on login and creates:
- Service file: `~/Library/LaunchAgents/com.transcraib-agent.plist`
- Auto-start on login
- Automatic restart if crashed

```bash
# Manual service control
launchctl load ~/Library/LaunchAgents/com.transcraib-agent.plist
launchctl unload ~/Library/LaunchAgents/com.transcraib-agent.plist
```

### Linux (systemd)

The service runs as a user service and creates:
- Service file: `~/.config/systemd/user/transcraib-agent.service`
- Auto-start on login
- Automatic restart if crashed

```bash
# Manual service control
systemctl --user start transcraib-agent
systemctl --user stop transcraib-agent
systemctl --user status transcraib-agent
```

## Troubleshooting

### Common Issues

#### "Command not found: jq"
**Solution**: Install jq manually
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

#### "fswatch not found" (macOS)
**Solution**: Install fswatch
```bash
brew install fswatch
```

#### "Operation not permitted" (macOS)
**Solution**: Grant Full Disk Access to Terminal (see Permissions section)

#### Voice Memos LaunchAgent Issues
**Symptoms**: Service restarting, "Operation not permitted" errors
**Solution**: Use screen-based background mode or foreground mode for Voice Memos

#### Files not being detected
**Checks**:
1. Verify directory exists: `ls -la ~/path/to/directory`
2. Check configuration: `cat ~/.transcraib-agent/config.json`
3. Verify extensions match: files must have exact extension match
4. Check logs: `tail -f ~/.transcraib-agent/transcraib-agent.log`

#### Service not starting
**Checks**:
1. Check service status: `./transcraib-agent.sh --status`
2. Test manual run: `./transcraib-agent.sh --monitor`
3. Check configuration: `./transcraib-agent.sh --configure`
4. Review logs for errors

### Log Analysis

Logs are stored in `~/.transcraib-agent/transcraib-agent.log`:

```bash
# View recent logs
tail -f ~/.transcraib-agent/transcraib-agent.log

# Search for errors
grep ERROR ~/.transcraib-agent/transcraib-agent.log

# View startup messages
grep "Starting Transcraib Agent" ~/.transcraib-agent/transcraib-agent.log
```

### Configuration Validation

Test your configuration:
```bash
# Validate JSON syntax
jq empty ~/.transcraib-agent/config.json

# Show parsed configuration
jq . ~/.transcraib-agent/config.json

# Test file access
ls -la "$(jq -r '.destination' ~/.transcraib-agent/config.json)"
```

## Advanced Usage

### Custom Extensions

Add any file extension to monitor:
```json
"extensions": ["pdf", "doc", "docx", "txt", "rtf", "pages"]
```

### Multiple Tags for Same Directory

Monitor the same directory with different tags:
```json
[
  {
    "name": "desktop_images",
    "path": "~/Desktop",
    "extensions": ["jpg", "png", "gif"],
    "tag": "image",
    "enabled": true
  },
  {
    "name": "desktop_docs",
    "path": "~/Desktop", 
    "extensions": ["pdf", "doc"],
    "tag": "document",
    "enabled": true
  }
]
```

### Network/Cloud Destinations

Use any accessible directory as destination:
```json
"destination": "/Volumes/NetworkDrive/organized"
"destination": "~/Google Drive/auto-organized"
"destination": "~/OneDrive/transcraib-files"
```

### Subdirectory Monitoring

Currently monitors only the direct directory (depth 1). For subdirectories, add separate entries:
```json
[
  {
    "name": "documents_root",
    "path": "~/Documents",
    "extensions": ["pdf"],
    "tag": "doc",
    "enabled": true
  },
  {
    "name": "documents_work",
    "path": "~/Documents/Work",
    "extensions": ["pdf"],
    "tag": "work",
    "enabled": true
  }
]
```

## Performance Considerations

### Real-time vs Polling

- **Real-time** (fswatch/inotify): Immediate detection, lower CPU usage
- **Polling** (fallback): 5-second intervals, higher CPU usage but more compatible

### File System Events

The agent monitors:
- **New files** created in watched directories
- **Modified files** (existing files that change)
- **Moved files** into watched directories

### Resource Usage

- **CPU**: Very low when using real-time monitoring
- **Memory**: Minimal (typically <10MB)
- **Disk**: Only for copying files and small log files
- **Network**: None (unless destination is network drive)

## Uninstallation

### Complete Removal

```bash
# Stop and remove service
./transcraib-agent.sh --uninstall

# Remove configuration and logs
rm -rf ~/.transcraib-agent

# Remove script
rm transcraib-agent.sh
```

### Keep Configuration

```bash
# Stop service only
./transcraib-agent.sh --uninstall

# Keep ~/.transcraib-agent directory for future use
```

## Changelog

### Version 2.0.2 (2025-05-25)
- **Fixed**: Logging bug that reported false "Failed to copy" errors when files were successfully processed
- **Fixed**: LaunchAgent PATH environment to include Homebrew directories for fswatch access
- **Added**: macOS Voice Memos LaunchAgent permission documentation and workarounds
- **Added**: Screen-based background monitoring alternative for Voice Memos access
- **Improved**: Full Disk Access setup instructions with Cmd+Shift+G navigation
- **Improved**: Real-time monitoring now works correctly in both foreground and background modes

### Version 2.0.1 (2024-05-24)
- **Fixed**: Bash compatibility issues with older bash versions (macOS 3.x)
- **Fixed**: Duplicate logging output (messages appearing twice)
- **Improved**: Cross-platform associative array handling
- **Improved**: Cleaner console output with proper log separation

### Version 2.0.0 (2024-05-24)
- **Major rewrite**: Merged separate config and monitoring scripts
- **Added**: Real-time monitoring with fswatch/inotify
- **Added**: Cross-platform support (macOS + Linux)
- **Added**: Automatic service installation (LaunchAgent/systemd)
- **Added**: JSON-based configuration
- **Added**: Interactive configuration wizard
- **Added**: Comprehensive logging with colors
- **Added**: Automatic dependency installation
- **Improved**: Error handling and validation
- **Improved**: File processing with better duplicate detection

### Version 1.0.0 (Previous)
- Initial bash implementation
- Basic polling-based monitoring
- Simple key=value configuration
- Manual installation process

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on both macOS and Linux
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Support

- **Issues**: Report bugs and request features via GitHub Issues
- **Documentation**: This README covers most use cases
- **Logs**: Check `~/.transcraib-agent/transcraib-agent.log` for troubleshooting

---

**Transcraib Agent** - Keeping your files organized automatically! 🚀
