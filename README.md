# MPV Pi Player

A complete media player system for Raspberry Pi with web interface, Node-RED API, and multi-player synchronization support.

## Features

- 🎬 **MPV-based video playback** optimized for Raspberry Pi 4
- 🌐 **Web interface** with dark theme for easy control
- 🔌 **Node-RED API** for automation and integration
- 🔄 **Multi-player sync** - Control multiple players from a master device
- 📁 **File management** - Upload, play, and delete videos
- 🎮 **Full playback control** - Play, pause, stop, skip, seek
- 🔊 **Volume control** with HDMI audio output
- 🖥️ **Clean black screen** when idle (no console text)

## One-Line Installation

SSH into your Raspberry Pi running Raspberry Pi OS Lite and run:

```bash
curl -sSL https://raw.githubusercontent.com/keep-on-walking/mpv-pi-player/main/install.sh | bash
```

This installer will:
- Install all dependencies (MPV, Python, etc.)
- Configure display for black screen when idle  
- Set HDMI 0 as audio output
- Set up the web interface
- Configure the service to start on boot
- Create video storage directory
- Reboot the system automatically

## Access the Player

After installation and reboot:

1. **Web Interface**: `http://[YOUR_PI_IP]:5000`
2. **Upload videos** through the web interface
3. **Control playback** using the web controls or Node-RED

## Node-RED Integration

### Quick Setup
1. Import `examples/node-red-flows.json` into Node-RED
2. Replace `{{PI_IP}}` with your Raspberry Pi's IP address
3. Deploy the flow

### API Endpoints

| Method | Endpoint | Description | Payload |
|--------|----------|-------------|---------|
| POST | `/api/play` | Play video | `{"file": "video.mp4"}` |
| POST | `/api/pause` | Toggle pause | - |
| POST | `/api/stop` | Stop playback | - |
| POST | `/api/skip` | Skip forward/backward | `{"seconds": 30}` |
| POST | `/api/seek` | Seek to position | `{"position": 300}` |
| POST | `/api/volume` | Set volume | `{"level": 50}` |
| GET | `/api/status` | Get player status | - |
| GET | `/api/files` | List media files | - |

## Multi-Player Synchronization

### Master Setup
1. Open web interface
2. Go to "Multi-Player Sync" section
3. Click "SET AS MASTER"

### Slave Setup
1. Open web interface on slave Pi
2. Go to "Multi-Player Sync" section  
3. Enter master's IP address
4. Click "CONNECT TO MASTER"

Slave players will automatically sync with the master's playback.

## File Structure

```
/home/pi/
├── mpv-pi-player/        # Application directory
│   ├── app.py            # Main Flask application
│   ├── mpv_controller.py # MPV control module
│   ├── sync_manager.py   # Sync functionality
│   ├── static/           # CSS and JavaScript
│   ├── templates/        # HTML templates
│   └── venv/             # Python virtual environment
└── videos/               # Video storage directory
```

## Configuration

Edit `/home/pi/mpv-player-config.json` to customize:

```json
{
  "media_dir": "/home/pi/videos",
  "max_upload_size": 2147483648,
  "volume": 100,
  "sync_mode": "standalone",
  "hardware_accel": true
}
```

## Service Management

```bash
# Check service status
sudo systemctl status mpv-player.service

# View logs
sudo journalctl -u mpv-player.service -f

# Restart service
sudo systemctl restart mpv-player.service

# Stop service
sudo systemctl stop mpv-player.service
```

## Troubleshooting

### No Video Output
- Ensure HDMI cable is connected before boot
- Check that video file exists in `/home/pi/videos/`
- View logs: `sudo journalctl -u mpv-player.service -n 50`

### No Audio
- Verify TV/monitor has speakers
- Check TV audio isn't muted
- Test audio: `speaker-test -D hw:0,0 -c 2 -l 1`

### Web Interface Not Loading
- Check Pi's IP address: `hostname -I`
- Ensure service is running: `sudo systemctl status mpv-player.service`
- Check firewall isn't blocking port 5000

### Upload Fails
- Check file size (max 2GB by default)
- Ensure enough disk space: `df -h`
- Check permissions: `ls -la /home/pi/videos/`

## System Requirements

- Raspberry Pi 4 (recommended) or Pi 3B+
- Raspberry Pi OS Lite (64-bit recommended)
- 8GB+ SD card
- HDMI display
- Network connection

## What Gets Installed

- MPV media player with hardware acceleration
- Python 3 with Flask web framework
- WebSocket support for synchronization
- ALSA audio utilities
- Graphics libraries for DRM output

## License

MIT License - See LICENSE file for details

## Support

For issues or questions, please open an issue on GitHub.
