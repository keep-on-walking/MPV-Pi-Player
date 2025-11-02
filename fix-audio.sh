#!/bin/bash

echo "==================================="
echo "MPV Pi Player Audio Diagnostic & Fix"
echo "==================================="
echo ""

# Check if running on Raspberry Pi
if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model)
    echo "Device: $MODEL"
    echo ""
fi

echo "1. Checking available audio devices..."
echo "---------------------------------------"
echo "ALSA devices:"
aplay -l
echo ""

echo "2. Checking current ALSA configuration..."
echo "---------------------------------------"
if [ -f /proc/asound/card*/id ]; then
    echo "Active sound cards:"
    cat /proc/asound/card*/id
fi
echo ""

echo "3. Checking PulseAudio status..."
echo "---------------------------------------"
if command -v pactl &> /dev/null; then
    echo "PulseAudio is installed"
    pactl info | grep -E 'Server Name|Default Sink|Default Source' || echo "PulseAudio not running"
    echo ""
    echo "Available PulseAudio sinks:"
    pactl list sinks short 2>/dev/null || echo "No sinks available"
else
    echo "PulseAudio not installed"
fi
echo ""

echo "4. Testing MPV audio devices..."
echo "---------------------------------------"
echo "Available MPV audio devices:"
mpv --audio-device=help 2>&1 | grep -E '^\s+' | head -20
echo ""

echo "5. Checking current MPV configuration..."
echo "---------------------------------------"
if [ -f "$HOME/MPV Pi Player/config.json" ]; then
    echo "Current audio device in config:"
    grep -E '"audio_device"|"audio_output"' "$HOME/MPV Pi Player/config.json"
fi
echo ""

echo "6. Testing audio output..."
echo "---------------------------------------"
read -p "Do you want to test audio output? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Testing with speaker-test (2 seconds)..."
    timeout 2 speaker-test -c 2 -t wav 2>/dev/null || echo "Speaker test failed"
fi
echo ""

echo "7. Applying fixes..."
echo "---------------------------------------"

# Determine the best audio device
AUDIO_DEVICE=""

# Check for Raspberry Pi 4 HDMI audio (vc4-hdmi)
if aplay -l | grep -q "vc4-hdmi"; then
    echo "Raspberry Pi 4 HDMI audio detected (vc4-hdmi)"
    # Check for vc4hdmi0 (HDMI port 0)
    if aplay -l | grep -q "vc4hdmi0"; then
        AUDIO_DEVICE="alsa/hdmi:CARD=vc4hdmi0,DEV=0"
        echo "Using HDMI port 0 (vc4hdmi0)"
    # Check for vc4hdmi1 (HDMI port 1)
    elif aplay -l | grep -q "vc4hdmi1"; then
        AUDIO_DEVICE="alsa/hdmi:CARD=vc4hdmi1,DEV=0"
        echo "Using HDMI port 1 (vc4hdmi1)"
    else
        AUDIO_DEVICE="alsa/hdmi:CARD=vc4hdmi,DEV=0"
        echo "Using vc4-hdmi audio"
    fi
# Check for older Pi HDMI audio
elif aplay -l | grep -q "HDMI"; then
    echo "Standard HDMI audio detected"
    # Try to find the HDMI device
    if aplay -l | grep -q "card 0.*HDMI"; then
        AUDIO_DEVICE="alsa/hdmi:CARD=HDMI,DEV=0"
        echo "Using HDMI audio on card 0"
    elif aplay -l | grep -q "card 1.*HDMI"; then
        AUDIO_DEVICE="alsa/hdmi:CARD=HDMI,DEV=0"
        echo "Using HDMI audio on card 1"
    fi
# Check for headphone jack
elif aplay -l | grep -q "bcm2835.*Headphones"; then
    echo "Headphone jack detected"
    AUDIO_DEVICE="alsa/default"
# Default to auto
else
    echo "Using automatic audio selection"
    AUDIO_DEVICE="auto"
fi

# Update the mpv_controller.py with the correct audio device
if [ -n "$AUDIO_DEVICE" ] && [ "$AUDIO_DEVICE" != "auto" ]; then
    echo ""
    echo "Updating MPV controller with audio device: $AUDIO_DEVICE"
    
    # Backup the original file
    cp "$HOME/MPV Pi Player/mpv_controller.py" "$HOME/MPV Pi Player/mpv_controller.py.backup"
    
    # Update the audio device in mpv_controller.py
    cat > /tmp/audio_fix.py << 'EOF'
import sys
import re

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Update the audio device line
content = re.sub(
    r"'--audio-device=.*?'",
    f"'--audio-device={sys.argv[2]}'",
    content
)

# If no audio-device line exists, add it after vo=gpu
if '--audio-device=' not in content:
    content = re.sub(
        r"('--vo=gpu',)",
        f"\\1\n            '--audio-device={sys.argv[2]}',",
        content
    )

with open(sys.argv[1], 'w') as f:
    f.write(content)
EOF
    
    python3 /tmp/audio_fix.py "$HOME/MPV Pi Player/mpv_controller.py" "$AUDIO_DEVICE"
    rm /tmp/audio_fix.py
    
    echo "Updated mpv_controller.py"
fi

# Create an ALSA configuration file if needed
if [ ! -f "$HOME/.asoundrc" ]; then
    echo ""
    echo "Creating ALSA configuration..."
    cat > "$HOME/.asoundrc" << 'EOF'
# Default to HDMI if available, otherwise use headphones
pcm.!default {
    type asym
    playback.pcm {
        type plug
        slave.pcm "output"
    }
    capture.pcm {
        type plug
        slave.pcm "input"
    }
}

pcm.output {
    type hw
    card 0
    device 0
}

pcm.input {
    type hw
    card 0
    device 0
}
EOF
    echo "Created ~/.asoundrc"
fi

# Set audio output to HDMI if using desktop
if [ -n "$DISPLAY" ]; then
    echo ""
    echo "Setting audio output to HDMI (if available)..."
    # Force audio to HDMI
    amixer cset numid=3 2 2>/dev/null || echo "Could not set audio to HDMI using amixer"
    
    # Alternative method using raspi-config non-interactively
    if command -v raspi-config &> /dev/null; then
        sudo raspi-config nonint do_audio 2 2>/dev/null || echo "Could not set audio using raspi-config"
    fi
fi

echo ""
echo "8. Restarting MPV player service..."
echo "---------------------------------------"
sudo systemctl restart mpv-player.service
sleep 2
sudo systemctl status mpv-player.service --no-pager | head -15

echo ""
echo "==================================="
echo "Audio fix complete!"
echo "==================================="
echo ""
echo "To manually test different audio outputs:"
echo "  mpv --audio-device=alsa/hdmi:CARD=HDMI,DEV=0 test.mp4  # For HDMI"
echo "  mpv --audio-device=alsa/default test.mp4               # For default"
echo "  mpv --audio-device=auto test.mp4                        # For automatic"
echo ""
echo "To see all available devices:"
echo "  mpv --audio-device=help"
echo ""
echo "If audio still doesn't work:"
echo "1. Check your HDMI cable connection"
echo "2. Ensure your monitor/TV volume is not muted"
echo "3. Try: sudo raspi-config > Advanced Options > Audio > Force HDMI"
echo ""
