#!/bin/bash

# Constants
CONFIG_PATH="$HOME/.transcraib_config"
SUGGESTED_DEST_DIR="$HOME/Dropbox"

# Source Directories Configuration
# Format: "directory:tag:extension"
declare -a SOURCE_DIRS=(
    # System Files
    "$HOME/Desktop:desktop:.pdf"              # PDFs on Desktop
    "$HOME/Downloads:downloads:.pdf"          # PDFs in Downloads
    "$HOME/Documents:documents:.pdf"          # PDFs in Documents
    
    # Media Files
    "$HOME/Pictures:pictures:.jpg"            # JPG images
    "$HOME/Pictures:pictures:.png"            # PNG images
    "$HOME/Movies:movies:.mp4"                # MP4 videos
    "$HOME/Movies:movies:.mov"                # MOV videos
    
    # Special Locations
    "$HOME/Documents/PDFs:documents_pdfs:.pdf"  # PDFs in Documents/PDFs
)

# Handle Ctrl+C gracefully
trap 'echo -e "\nOperation cancelled"; exit 1' INT

# Simple directory validation
validate_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Directory does not exist: $dir"
        return 1
    fi
    if [ ! -r "$dir" ]; then
        echo "Directory is not readable: $dir"
        return 1
    fi
    return 0
}

# Get destination directory
get_destination() {
    local dir=""
    while true; do
        echo -e "\nStep 1: Choose Destination Directory"
        echo "--------------------------------"
        echo "This is where your monitored files will be copied to."
        echo
        echo "Default: $SUGGESTED_DEST_DIR"
        echo "• Press Enter to use this location"
        echo "• Or type a different path (e.g., ~/Documents/Organized)"
        echo
        printf "Enter path [default: $SUGGESTED_DEST_DIR]: "
        read -r input
        
        # Use default if empty
        dir="${input:-$SUGGESTED_DEST_DIR}"
        
        # Expand ~ if present
        dir="${dir/#\~/$HOME}"
        
        # Remove trailing slash
        dir="${dir%/}"
        
        if [ ! -d "$dir" ]; then
            echo "Directory does not exist. Create it? (y/n)"
            read -r -n 1 create
            echo
            if [[ "$create" =~ ^[Yy]$ ]]; then
                if mkdir -p "$dir"; then
                    echo "✓ Created directory: $dir"
                    break
                else
                    echo "Failed to create directory"
                fi
            fi
        else
            if [ -r "$dir" ]; then
                echo "✓ Directory is valid"
                break
            else
                echo "Directory exists but is not readable"
            fi
        fi
    done
    echo "$dir"
}

# Select source directories
select_sources() {
    local -a selected=()
    
    echo -e "\nStep 2: Choose Directories to Monitor"
    echo "--------------------------------"
    echo "Select which directories to watch for files:"
    echo
    
    # Display available sources with numbers
    local number=1
    for source in "${SOURCE_DIRS[@]}"; do
        local dir="${source%%:*}"
        local tag="${source#*:}"; tag="${tag%%:*}"
        local ext="${source##*:}"
        
        # Expand $HOME in directory path for display
        dir="${dir/#\$HOME/$HOME}"
        
        # Show all directories, indicate if not accessible
        if [ -d "$dir" ] && [ -r "$dir" ]; then
            printf "\n%2d) [%s] %s\n" "$number" "$tag" "$dir"
            printf "   • Monitors: *%s files\n" "$ext"
            echo   "   ✓ Directory is accessible"
        else
            printf "\n%2d) [%s] %s\n" "$number" "$tag" "$dir"
            printf "   • Monitors: *%s files\n" "$ext"
            echo   "   ✗ Directory not accessible (will be skipped)"
        fi
        ((number++))
    done
    
    echo -e "\nHow to select:"
    echo "1. Type a number and press Enter"
    echo "2. Repeat for each directory you want"
    echo "3. Type 0 and press Enter when done"
    echo
    echo "Example: To select first two directories:"
    echo "> 1 [Enter]"
    echo "> 2 [Enter]"
    echo "> 0 [Enter]"
    echo
    
    while true; do
        printf "\nEnter a number (1-%d, or 0 to finish): " "$((number-1))"
        read -r num
        
        if [ "$num" = "0" ]; then
            break
        fi
        
        if [[ "$num" =~ ^[0-9]+$ ]] && ((num > 0 && num < number)); then
            local source="${SOURCE_DIRS[$((num-1))]}"
            local dir="${source%%:*}"
            dir="${dir/#\$HOME/$HOME}"
            
            if [ -d "$dir" ] && [ -r "$dir" ]; then
                selected+=("$source")
                echo "✓ Added: $dir"
            else
                echo "✗ Directory not accessible: $dir"
            fi
        else
            echo "Invalid selection. Enter a number between 1 and $((number-1)), or 0 to finish."
        fi
    done
    
    echo "${selected[@]}"
}

# Add custom source directory
add_custom_source() {
    local dir=""
    local tag=""
    local ext=""
    
    echo -e "\nAdd Custom Directory"
    echo "-------------------------"
    echo "You can monitor additional directories by specifying:"
    echo "1. The directory path to monitor"
    echo "2. A tag to identify files from this source"
    echo "3. The file extension to monitor"
    
    # Get directory
    while true; do
        echo -e "\nExample paths:"
        echo "• ~/Documents/Work"
        echo "• ~/Desktop/Projects"
        echo "• /Users/username/Downloads/Important"
        printf "\nEnter directory path: "
        read -r dir
        
        # Expand ~ if present
        dir="${dir/#\~/$HOME}"
        
        # Remove trailing slash
        dir="${dir%/}"
        
        if [ ! -d "$dir" ]; then
            echo "Directory does not exist. Create it? (y/n)"
            read -r -n 1 create
            echo
            if [[ "$create" =~ ^[Yy]$ ]]; then
                if mkdir -p "$dir"; then
                    echo "✓ Created directory: $dir"
                    break
                else
                    echo "Failed to create directory"
                fi
            fi
        else
            if [ -r "$dir" ]; then
                echo "✓ Directory is valid"
                break
            else
                echo "Directory exists but is not readable"
            fi
        fi
    done
    
    # Get tag
    echo -e "\nExample tags: work, personal, projects, receipts"
    printf "Enter tag for this directory [custom]: "
    read -r tag
    tag="${tag:-custom}"
    
    # Get extension
    echo -e "\nExample extensions: .pdf, .jpg, .png, .doc"
    printf "Enter file extension to monitor [.pdf]: "
    read -r ext
    ext="${ext:-.pdf}"
    
    echo "$dir:$tag:$ext"
}

# Main execution
clear
echo "Transcraib Configuration"
echo "======================"
echo "This tool helps you automatically organize files by:"
echo "1. Monitoring specific directories for new files"
echo "2. Copying them to a central location"
echo "3. Adding tags to identify their source"
echo
echo "The setup has 3 steps:"
echo "1. Choose where to store your organized files"
echo "2. Select which directories to monitor"
echo "3. Optionally add custom directories"
echo
echo "Press Enter to begin..."
read -r

# Get destination directory
dest_dir=$(get_destination)

# Select source directories
selected_sources=($(select_sources))

# Ask for custom sources
while true; do
    echo -e "\nStep 3: Add Custom Directories (Optional)"
    echo "--------------------------------"
    echo "You can monitor additional directories beyond the defaults."
    echo -e "\nWould you like to add a custom directory? (y/n)"
    read -r -n 1 add_custom
    echo
    
    if [[ ! "$add_custom" =~ ^[Yy]$ ]]; then
        break
    fi
    
    custom_source=$(add_custom_source)
    if [ -n "$custom_source" ]; then
        selected_sources+=("$custom_source")
    fi
done

# Save configuration
{
    echo "DEST_DIR=$dest_dir"
    for source in "${selected_sources[@]}"; do
        echo "SOURCE=$source"
    done
} > "$CONFIG_PATH"

echo -e "\nConfiguration Complete!"
echo "======================="
echo "Your settings have been saved to: $CONFIG_PATH"
echo -e "\nWhat happens next:"
echo "1. The agent needs to be installed to start monitoring"
echo "2. Run this command: transcraib_agent.sh --install"
echo "3. The agent will run in the background"
echo "4. New files in monitored directories will be automatically copied"
echo -e "\nTo start monitoring, run:"
echo "bash transcraib_agent.sh --install"
