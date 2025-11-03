#!/bin/bash

echo "==================================="
echo "MPV Pi Player Diagnostic Tool"
echo "==================================="
echo ""
echo "Diagnosing video playback issues..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check system info
echo "1. System Information"
echo "---------------------------------------"
if [ -f /proc/device-tree/model ]; then
    echo "Device: $(cat /proc/device-tree/model)"
fi
echo "Kernel: $(uname -r)"
echo "Storage devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "sd|mmcblk|nvme"
echo ""

# Check service status
echo "2. Service Status"
echo "---------------------------------------"
if systemctl is-active --quiet mpv-player.service; then
    echo -e "${GREEN}✓${NC} MPV player service is running"
else
    echo -e "${RED}✗${NC} MPV player service is not running"
    echo "Starting service..."
    sudo systemctl start mpv-player.service
    sleep 2
fi
echo ""

# Check installation paths
echo "3. Installation Paths"
echo "---------------------------------------"
INSTALL_PATHS=(
    "$HOME/mpv-pi-player"
    "$HOME/MPV Pi Player"
    "$HOME/MPV-Pi-Player"
)

FOUND_PATH=""
for path in "${INSTALL_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo -e "${GREEN}✓${NC} Found installation at: $path"
        FOUND_PATH="$path"
        break
    fi
done

if [ -z "$FOUND_PATH" ]; then
    echo -e "${RED}✗${NC} Installation not found in expected locations"
    echo "Please specify your installation path"
    exit 1
fi
echo ""

# Check media directories
echo "4. Media Directories"
echo "---------------------------------------"
MEDIA_DIRS=(
    "$FOUND_PATH/media"
    "$HOME/media"
    "$HOME/videos"
    "/media"
    "/home/$(whoami)/media"
    "/home/$(whoami)/videos"
)

echo "Checking for media directories and video files:"
for dir in "${MEDIA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        VIDEO_COUNT=$(find "$dir" -maxdepth 2 -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" \) 2>/dev/null | wc -l)
        if [ $VIDEO_COUNT -gt 0 ]; then
            echo -e "${GREEN}✓${NC} $dir (contains $VIDEO_COUNT video files)"
            ls -la "$dir" | grep -E "\.(mp4|avi|mkv|mov)" | head -5
        else
            echo -e "${YELLOW}○${NC} $dir (exists but no video files found)"
        fi
    fi
done
echo ""

# Check permissions
echo "5. File Permissions"
echo "---------------------------------------"
echo "Checking permissions for app.py:"
if [ -f "$FOUND_PATH/app.py" ]; then
    ls -la "$FOUND_PATH/app.py"
    if [ -r "$FOUND_PATH/app.py" ]; then
        echo -e "${GREEN}✓${NC} app.py is readable"
    else
        echo -e "${RED}✗${NC} app.py is not readable"
    fi
fi

echo ""
echo "Checking media directory permissions:"
if [ -d "$FOUND_PATH/media" ]; then
    ls -ld "$FOUND_PATH/media"
    if [ -w "$FOUND_PATH/media" ]; then
        echo -e "${GREEN}✓${NC} media directory is writable"
    else
        echo -e "${RED}✗${NC} media directory is not writable"
        echo "Fixing permissions..."
        chmod 755 "$FOUND_PATH/media"
    fi
fi
echo ""

# Check if MPV is installed
echo "6. MPV Installation"
echo "---------------------------------------"
if command -v mpv &> /dev/null; then
    echo -e "${GREEN}✓${NC} MPV is installed"
    mpv --version | head -1
else
    echo -e "${RED}✗${NC} MPV is not installed"
    echo "Installing MPV..."
    sudo apt-get update && sudo apt-get install -y mpv
fi
echo ""

# Check port availability
echo "7. Port Availability"
echo "---------------------------------------"
PORT=$(grep -oP '"port":\s*\K\d+' "$FOUND_PATH/config.json" 2>/dev/null || echo "8080")
if netstat -tuln | grep -q ":$PORT "; then
    echo -e "${GREEN}✓${NC} Port $PORT is in use (should be by our app)"
    echo "Process using port $PORT:"
    sudo lsof -i :$PORT | tail -1
else
    echo -e "${YELLOW}○${NC} Port $PORT is not in use"
fi
echo ""

# Check Python dependencies
echo "8. Python Dependencies"
echo "---------------------------------------"
if [ -d "$FOUND_PATH/venv" ]; then
    echo -e "${GREEN}✓${NC} Virtual environment found"
    source "$FOUND_PATH/venv/bin/activate"
    
    # Check required packages
    REQUIRED_PACKAGES=("flask" "flask-cors" "werkzeug")
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if pip show $package &>/dev/null; then
            echo -e "${GREEN}✓${NC} $package is installed"
        else
            echo -e "${RED}✗${NC} $package is missing"
            pip install $package
        fi
    done
    deactivate
else
    echo -e "${RED}✗${NC} Virtual environment not found"
    echo "Creating virtual environment..."
    cd "$FOUND_PATH"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate
fi
echo ""

# Check logs
echo "9. Recent Log Entries"
echo "---------------------------------------"
echo "Last 20 lines from service log:"
journalctl -u mpv-player.service -n 20 --no-pager
echo ""

# Check disk space
echo "10. Disk Space"
echo "---------------------------------------"
df -h | grep -E "^/dev|Filesystem"
echo ""

# Test MPV directly
echo "11. MPV Direct Test"
echo "---------------------------------------"
echo "Testing MPV with a sample video..."
TEST_VIDEO=""
for dir in "${MEDIA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        TEST_VIDEO=$(find "$dir" -maxdepth 2 -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" \) 2>/dev/null | head -1)
        if [ -n "$TEST_VIDEO" ]; then
            break
        fi
    fi
done

if [ -n "$TEST_VIDEO" ]; then
    echo "Found test video: $TEST_VIDEO"
    echo "Testing playback (5 seconds)..."
    timeout 5 mpv --vo=drm --hwdec=auto-copy "$TEST_VIDEO" 2>&1 | grep -E "Playing:|Video:|Audio:|Error"
else
    echo -e "${YELLOW}○${NC} No video files found to test"
fi
echo ""

# Check config file
echo "12. Configuration File"
echo "---------------------------------------"
if [ -f "$FOUND_PATH/config.json" ]; then
    echo "config.json contents:"
    cat "$FOUND_PATH/config.json"
else
    echo -e "${RED}✗${NC} config.json not found"
fi
echo ""

# Suggest fixes
echo "==================================="
echo "Suggested Fixes"
echo "==================================="
echo ""

# Check if media directory needs to be created
if [ ! -d "$FOUND_PATH/media" ]; then
    echo "1. Create media directory:"
    echo "   mkdir -p '$FOUND_PATH/media'"
    echo ""
fi

# Check if videos need to be copied
VIDEO_COUNT=$(find "$FOUND_PATH/media" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" \) 2>/dev/null | wc -l)
if [ $VIDEO_COUNT -eq 0 ]; then
    echo "2. Copy video files to media directory:"
    echo "   cp /path/to/your/videos/*.mp4 '$FOUND_PATH/media/'"
    echo ""
fi

# Check if service needs restart
echo "3. Restart the service:"
echo "   sudo systemctl restart mpv-player.service"
echo ""

echo "4. Check the web interface:"
echo "   http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""

echo "5. If videos still won't play, check the browser console for errors:"
echo "   Press F12 in your browser and check the Console tab"
echo ""

echo "==================================="
echo "Quick Fix Script"
echo "==================================="
cat << 'FIXSCRIPT'

# Run this to apply common fixes:
cd "$HOME/mpv-pi-player" || cd "$HOME/MPV Pi Player" || cd "$HOME/MPV-Pi-Player"

# Create media directory if missing
mkdir -p media
chmod 755 media

# Set correct permissions
chmod +x app.py
chmod +x mpv_controller.py

# Restart service
sudo systemctl daemon-reload
sudo systemctl restart mpv-player.service

# Check status
sleep 3
sudo systemctl status mpv-player.service

echo "Try accessing: http://$(hostname -I | awk '{print $1}'):8080"

FIXSCRIPT

echo ""
echo "Diagnostic complete!"
