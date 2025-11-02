#!/bin/bash

# MPV Pi Player - Complete Installation Script
# One-command installer with all fixes integrated
# For Raspberry Pi OS Lite
# Usage: curl -sSL https://raw.githubusercontent.com/keep-on-walking/mpv-pi-player/main/install.sh | bash

set -e

echo "========================================="
echo "    MPV Pi Player Installation"
echo "========================================="
echo ""

# Detect current user and home directory
CURRENT_USER="${SUDO_USER:-$USER}"
HOME_DIR="/home/$CURRENT_USER"
INSTALL_DIR="$HOME_DIR/mpv-pi-player"
REPO_URL="https://github.com/keep-on-walking/mpv-pi-player.git"

# Detect boot partition location
if [ -d "/boot/firmware" ]; then
    BOOT_DIR="/boot/firmware"
else
    BOOT_DIR="/boot"
fi

echo "Configuration:"
echo "  User: $CURRENT_USER"
echo "  Home: $HOME_DIR"
echo "  Boot: $BOOT_DIR"
echo ""

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    echo "Warning: This doesn't appear to be a Raspberry Pi"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Updating system packages..."
sudo apt-get update

echo ""
echo "Step 2: Installing dependencies..."

# Install core dependencies
sudo apt-get install -y \
    mpv \
    python3 \
    python3-pip \
    python3-venv \
    git \
    wget \
    curl \
    alsa-utils

# Install graphics libraries with fallbacks
sudo apt-get install -y \
    libgbm1 \
    libdrm2 \
    libgl1-mesa-dri \
    libglx-mesa0 || true

# Optional graphics packages
sudo apt-get install -y libgles2-mesa 2>/dev/null || \
    sudo apt-get install -y libgles2 2>/dev/null || true

sudo apt-get install -y libegl1-mesa 2>/dev/null || \
    sudo apt-get install -y libegl1 2>/dev/null || true

# Install remaining dependencies
sudo apt-get install -y \
    libx11-6 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxtst6 \
    ca-certificates \
    fonts-liberation \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxinerama1 \
    lsb-release \
    xdg-utils || true

echo ""
echo "Step 3: Configuring display for black screen..."

# Disable cloud-init services if present
if systemctl list-units --all | grep -q cloud-init; then
    echo "Disabling cloud-init services..."
    sudo systemctl disable cloud-init.service 2>/dev/null || true
    sudo systemctl disable cloud-init-local.service 2>/dev/null || true
    sudo systemctl disable cloud-config.service 2>/dev/null || true
    sudo systemctl disable cloud-final.service 2>/dev/null || true
    sudo touch /etc/cloud/cloud-init.disabled
fi

# Configure boot for black screen
if [ -f "$BOOT_DIR/cmdline.txt" ]; then
    sudo cp "$BOOT_DIR/cmdline.txt" "$BOOT_DIR/cmdline.txt.backup-$(date +%Y%m%d)" 2>/dev/null || true
    
    # Get current cmdline and clean it
    CMDLINE=$(cat "$BOOT_DIR/cmdline.txt" | tr '\n' ' ' | sed 's/  */ /g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/console=[^ ]*//g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/quiet//g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/splash//g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/loglevel=[0-9]//g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/logo.nologo//g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/vt.global_cursor_default=[0-9]//g')
    CMDLINE=$(echo "$CMDLINE" | sed 's/consoleblank=[0-9]//g')
    CMDLINE=$(echo "$CMDLINE" | tr -s ' ')
    
    # Add console settings for black screen
    echo "console=tty3 loglevel=3 quiet logo.nologo vt.global_cursor_default=0 $CMDLINE" | sudo tee "$BOOT_DIR/cmdline.txt" > /dev/null
fi

# Update config.txt for display and HDMI audio
if ! grep -q "# MPV Pi Player Settings" "$BOOT_DIR/config.txt" 2>/dev/null; then
    echo "" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "# MPV Pi Player Settings" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "disable_splash=1" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "disable_overscan=1" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "hdmi_force_hotplug=1" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "hdmi_group=1" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "hdmi_mode=16" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "hdmi_drive=2" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "max_framebuffers=2" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "gpu_mem=256" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "dtparam=audio=on" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
    echo "hdmi_force_edid_audio=1" | sudo tee -a "$BOOT_DIR/config.txt" > /dev/null
fi

# Disable getty on tty1
sudo systemctl disable getty@tty1.service 2>/dev/null || true

# Create display blanking service
sudo tee /etc/systemd/system/display-blank.service > /dev/null << 'EOF'
[Unit]
Description=Blank display on boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'clear > /dev/tty1'
ExecStart=/bin/sh -c 'setterm --cursor off > /dev/tty1'
StandardOutput=tty
StandardError=null
TTYPath=/dev/tty1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable display-blank.service

echo ""
echo "Step 4: Configuring HDMI audio (Card 0)..."

# Force HDMI audio to card 0
sudo raspi-config nonint do_audio 2 2>/dev/null || true

# Configure ALSA for HDMI 0
sudo tee /etc/asound.conf > /dev/null << 'EOF'
# Use HDMI 0 for audio output
defaults.pcm.card 0
defaults.ctl.card 0

pcm.!default {
    type hw
    card 0
    device 0
}

ctl.!default {
    type hw
    card 0
}
EOF

# Set user-specific ALSA config
sudo tee $HOME_DIR/.asoundrc > /dev/null << 'EOF'
# User-specific HDMI 0 setting
pcm.!default {
    type hw
    card 0
}

ctl.!default {
    type hw
    card 0
}

defaults.ctl.card 0
defaults.pcm.card 0
EOF

# Fix ownership of the file
sudo chown $CURRENT_USER:$CURRENT_USER $HOME_DIR/.asoundrc

# Create audio persistence service
sudo tee /etc/systemd/system/set-hdmi0-audio.service > /dev/null << EOF
[Unit]
Description=Set HDMI 0 as default audio
After=sound.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'amixer -c 0 sset PCM 100% unmute 2>/dev/null || true'
ExecStart=/bin/bash -c 'amixer -c 0 sset Master 100% unmute 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable set-hdmi0-audio.service

# Set volume
sudo amixer -c 0 sset PCM 100% unmute 2>/dev/null || true
sudo amixer -c 0 sset Master 100% unmute 2>/dev/null || true

echo ""
echo "Step 5: Downloading application files..."

# Create video directory
mkdir -p $HOME_DIR/videos

# Check if installation directory exists and handle it
cd $HOME_DIR
if [ -d "$INSTALL_DIR" ]; then
    # Check if it's a valid git repository
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo "Updating existing installation..."
        cd $INSTALL_DIR
        git pull origin main || true
    else
        echo "Removing incomplete installation..."
        sudo rm -rf $INSTALL_DIR
        echo "Cloning repository..."
        git clone $REPO_URL $INSTALL_DIR
    fi
else
    echo "Cloning repository..."
    git clone $REPO_URL $INSTALL_DIR
fi

# Ensure directories exist
mkdir -p $INSTALL_DIR/templates
mkdir -p $INSTALL_DIR/static

echo ""
echo "Step 6: Installing Python dependencies..."

cd $INSTALL_DIR

# Check if requirements.txt exists
if [ ! -f "requirements.txt" ]; then
    echo "Creating requirements.txt..."
    cat > requirements.txt << 'EOFREQ'
# MPV Pi Player - Python Dependencies

# Web Framework
Flask==2.3.3
flask-cors==4.0.0
Werkzeug==2.3.7

# WebSocket Support for Sync
websockets==11.0.3

# System utilities
psutil==5.9.5
EOFREQ
fi

# Create or recreate virtual environment
if [ -d "venv" ]; then
    echo "Removing old virtual environment..."
    rm -rf venv
fi

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

echo ""
echo "Step 7: Setting up systemd service..."

# Create systemd service
sudo tee /etc/systemd/system/mpv-player.service > /dev/null << EOF
[Unit]
Description=MPV Pi Player Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
Environment="DISPLAY=:0"
Environment="HOME=$HOME_DIR"
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStartPre=/bin/sleep 10
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable service
sudo systemctl daemon-reload
sudo systemctl enable mpv-player.service

echo ""
echo "Step 8: Creating default configuration..."

cat > $HOME_DIR/mpv-player-config.json << EOF
{
    "media_dir": "$HOME_DIR/videos",
    "max_upload_size": 2147483648,
    "volume": 100,
    "sync_mode": "standalone",
    "master_ip": "",
    "sync_port": 8765,
    "autoplay": false,
    "loop": false,
    "hardware_accel": true,
    "display_output": "HDMI-A-1"
}
EOF

echo ""
echo "Step 9: Setting permissions..."

sudo chown -R $CURRENT_USER:$CURRENT_USER $INSTALL_DIR
sudo chown -R $CURRENT_USER:$CURRENT_USER $HOME_DIR/videos
sudo chmod +x $INSTALL_DIR/*.py 2>/dev/null || true

echo ""
echo "Step 10: Starting the service..."

sudo systemctl start mpv-player.service

# Wait for service to start
sleep 5

# Check service status
if sudo systemctl is-active --quiet mpv-player.service; then
    echo ""
    echo "========================================="
    echo "    Installation Complete!"
    echo "========================================="
    echo ""
    IP=$(hostname -I | awk '{print $1}')
    echo "✓ Web Interface: http://$IP:5000"
    echo "✓ Node-RED API: http://$IP:5000/api"
    echo "✓ Video Folder: $HOME_DIR/videos"
    echo ""
    echo "Service status: $(sudo systemctl is-active mpv-player.service)"
    echo ""
    echo "Commands:"
    echo "  View logs: sudo journalctl -u mpv-player.service -f"
    echo "  Restart: sudo systemctl restart mpv-player.service"
    echo ""
    echo "The system will reboot in 10 seconds..."
    sleep 10
    sudo reboot
else
    echo ""
    echo "Warning: Service failed to start"
    echo "Check logs: sudo journalctl -u mpv-player.service -n 50"
    echo ""
    echo "Manual reboot recommended: sudo reboot"
fi


