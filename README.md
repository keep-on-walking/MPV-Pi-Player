# MPV Pi Player - Standalone Version

A powerful video player system for Raspberry Pi with web interface and API control.

## Features

- 🎬 **Hardware-accelerated video playback** using MPV
- 🌐 **Web Interface** for easy control from any device
- 📱 **Responsive Design** - works on phones, tablets, and desktops
- 🔌 **HTTP API** for Node-RED and automation integration
- 📁 **File Management** - upload, delete, and organize videos
- 🎮 **Full Playback Control** - play, pause, stop, seek, skip, volume
- 🖥️ **Headless Mode** - works with or without HDMI display connected
- 🔊 **HDMI Audio** - optimized for Raspberry Pi 4 audio output
- 📂 **Dynamic Path Detection** - works with any username or storage type

## Requirements

- Raspberry Pi (tested on Pi 3, Pi 4)
- Raspberry Pi OS Lite (recommended) or Desktop
- Python 3.7+
- Internet connection for installation

## Quick Installation

```bash
# One-line installer
curl -sSL https://raw.githubusercontent.com/keep-on-walking/MPV-Pi-Player/main/install.sh | bash
```

## Manual Installation

```bash
# Clone the repository
git clone https://github.com/keep-on-walking/MPV-Pi-Player.git
cd MPV-Pi-Player

# Run the installer
chmod +x install.sh
./install.sh
```

## Usage

### Web Interface
After installation, access the player at:
```
http://[your-pi-ip]:8080
```

### API Endpoints

Control the player via HTTP API:

- `GET /api/status` - Get player status
- `POST /api/play` - Play a video or resume
- `POST /api/pause` - Pause/resume playback  
- `POST /api/stop` - Stop playback
- `POST /api/seek` - Seek to position
- `POST /api/skip` - Skip forward/backward
- `POST /api/volume` - Set volume
- `GET /api/files` - List media files
- `POST /api/upload` - Upload new video
- `DELETE /api/files/{filename}` - Delete a video

### Node-RED Integration

Example flow to play a video:
```json
{
  "method": "POST",
  "url": "http://[pi-ip]:8080/api/play",
  "headers": {"Content-Type": "application/json"},
  "payload": {"file": "video.mp4"}
}
```

## File Structure

```
~/mpv-pi-player/
├── app.py              # Main application
├── mpv_controller.py   # MPV control module
├── config.json         # Configuration file
├── requirements.txt    # Python dependencies
├── static/            # Web interface assets
├── templates/         # HTML templates
└── media/            # Video files directory
```

## Configuration

Edit `config.json` to customize:
```json
{
  "port": 8080,
  "media_dir": "/home/pi/videos",
  "volume": 100,
  "hardware_accel": true,
  "loop": false
}
```

## Troubleshooting

### Diagnostic Tools

```bash
# Run diagnostic script
cd ~/mpv-pi-player
./diagnose.sh
```

### Audio Issues

If no audio through HDMI:
```bash
cd ~/mpv-pi-player
./fix-audio.sh
```

### Service Management

```bash
# Check service status
sudo systemctl status mpv-player.service

# View logs
journalctl -u mpv-player.service -f

# Restart service
sudo systemctl restart mpv-player.service
```

### Common Issues

1. **No video playback**
   - Check if videos are in `~/videos` directory
   - Verify file permissions: `chmod 644 ~/videos/*.mp4`

2. **No audio**
   - Run `./fix-audio.sh`
   - Check TV/monitor volume
   - Ensure HDMI cable supports audio

3. **Web interface not accessible**
   - Check firewall: `sudo ufw allow 8080`
   - Verify service is running: `systemctl status mpv-player`

4. **Videos won't upload**
   - Check disk space: `df -h`
   - Verify write permissions on media directory

## Supported Formats

- MP4, AVI, MKV, MOV
- WMV, FLV, WEBM, M4V
- MPG, MPEG, 3GP, OGV

## System Requirements

- **Minimum:** Raspberry Pi 3, 1GB RAM
- **Recommended:** Raspberry Pi 4, 2GB+ RAM
- **Storage:** Depends on video library size
- **Network:** Ethernet or WiFi for web access

## License

MIT License - see LICENSE file for details

## Support

For issues or questions:
- Create an issue on GitHub
- Check existing issues for solutions

## Credits

Built with:
- [MPV](https://mpv.io/) - Video player
- [Flask](https://flask.palletsprojects.com/) - Web framework
- [Bootstrap](https://getbootstrap.com/) - UI framework

