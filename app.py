#!/usr/bin/env python3
"""
MPV Pi Player - Main Application
Video player with web interface and HTTP API for Raspberry Pi
"""

import os
import sys
import json
import time
import logging
import threading
import asyncio
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify, render_template, send_from_directory
from flask_cors import CORS
from werkzeug.utils import secure_filename
from werkzeug.exceptions import RequestEntityTooLarge

# Import our modules
from mpv_controller import MPVController
from sync_manager import SyncManager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Flask application setup
app = Flask(__name__)
CORS(app)

# Configuration
HOME_DIR = os.path.expanduser('~')
INSTALL_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(INSTALL_DIR, 'config.json')
DEFAULT_CONFIG = {
    "port": 8080,
    "media_dir": os.path.join(HOME_DIR, "videos"),
    "max_upload_size": 2147483648,  # 2GB in bytes
    "volume": 100,
    "sync_mode": "standalone",  # "master", "slave", or "standalone"
    "master_ip": "",
    "sync_port": 8765,
    "autoplay": False,
    "loop": False,
    "hardware_accel": True,
    "display_output": "HDMI-A-1"
}

# Global variables
config = {}
player = None
sync_manager = None
start_time = time.time()

def load_config():
    """Load configuration from file"""
    global config
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                loaded_config = json.load(f)
                config = {**DEFAULT_CONFIG, **loaded_config}
        else:
            config = DEFAULT_CONFIG.copy()
            save_config()
    except Exception as e:
        logger.error(f"Error loading config: {e}")
        config = DEFAULT_CONFIG.copy()
    return config

def save_config():
    """Save configuration to file"""
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except Exception as e:
        logger.error(f"Error saving config: {e}")
        return False

def get_media_files():
    """Get list of media files in the media directory"""
    media_dir = config.get('media_dir', os.path.join(HOME_DIR, 'videos'))
    supported_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.3gp', '.ogv']
    
    files = []
    try:
        for file in Path(media_dir).iterdir():
            if file.is_file() and file.suffix.lower() in supported_extensions:
                files.append({
                    'name': file.name,
                    'size': file.stat().st_size,
                    'modified': datetime.fromtimestamp(file.stat().st_mtime).isoformat()
                })
    except Exception as e:
        logger.error(f"Error listing media files: {e}")
    
    return sorted(files, key=lambda x: x['name'].lower())

# Configure upload settings
app.config['MAX_CONTENT_LENGTH'] = DEFAULT_CONFIG['max_upload_size']
app.config['UPLOAD_FOLDER'] = DEFAULT_CONFIG['media_dir']

# Web routes
@app.route('/')
def index():
    """Main web interface"""
    return render_template('index.html')

# API routes for Node-RED integration
@app.route('/api/status', methods=['GET'])
def api_status():
    """Get current player status"""
    status = {
        'state': player.get_state(),
        'current_file': player.current_file,
        'position': player.get_position(),
        'duration': player.get_duration(),
        'volume': player.get_volume(),
        'sync_mode': config.get('sync_mode', 'standalone'),
        'hostname': os.uname().nodename
    }
    return jsonify(status)

@app.route('/api/play', methods=['POST'])
def api_play():
    """Start playback - can specify file or resume current"""
    data = request.get_json() or {}
    filename = data.get('file')
    
    if filename:
        filepath = os.path.join(config['media_dir'], filename)
        if os.path.exists(filepath):
            success = player.play(filepath)
            if success and config.get('sync_mode') == 'master':
                sync_manager.broadcast_command('play', {'file': filename})
            return jsonify({'success': success, 'message': f'Playing {filename}'})
        else:
            return jsonify({'success': False, 'message': 'File not found'}), 404
    else:
        # Resume playback
        success = player.resume()
        if success and config.get('sync_mode') == 'master':
            sync_manager.broadcast_command('resume', {})
        return jsonify({'success': success, 'message': 'Resumed playback'})

@app.route('/api/pause', methods=['POST'])
def api_pause():
    """Toggle pause/resume"""
    success = player.pause()
    if success and config.get('sync_mode') == 'master':
        sync_manager.broadcast_command('pause', {})
    return jsonify({'success': success, 'message': 'Toggled pause'})

@app.route('/api/stop', methods=['POST'])
def api_stop():
    """Stop playback"""
    success = player.stop()
    if success and config.get('sync_mode') == 'master':
        sync_manager.broadcast_command('stop', {})
    return jsonify({'success': success, 'message': 'Stopped playback'})

@app.route('/api/seek', methods=['POST'])
def api_seek():
    """Seek to specific position in seconds"""
    data = request.get_json() or {}
    position = data.get('position', 0)
    
    success = player.seek(position)
    if success and config.get('sync_mode') == 'master':
        sync_manager.broadcast_command('seek', {'position': position})
    return jsonify({'success': success, 'message': f'Seeked to {position}s'})

@app.route('/api/skip', methods=['POST'])
def api_skip():
    """Skip forward or backward by specified seconds (default 30)"""
    data = request.get_json() or {}
    seconds = data.get('seconds', 30)
    
    current_pos = player.get_position()
    new_pos = max(0, current_pos + seconds)
    
    success = player.seek(new_pos)
    if success and config.get('sync_mode') == 'master':
        sync_manager.broadcast_command('seek', {'position': new_pos})
    return jsonify({'success': success, 'message': f'Skipped {seconds}s', 'new_position': new_pos})

@app.route('/api/volume', methods=['POST'])
def api_volume():
    """Set volume level (0-100)"""
    data = request.get_json() or {}
    level = max(0, min(100, data.get('level', 100)))
    
    success = player.set_volume(level)
    if success:
        config['volume'] = level
        save_config()
    return jsonify({'success': success, 'message': f'Volume set to {level}%'})

@app.route('/api/files', methods=['GET'])
def api_files():
    """List available media files"""
    files = get_media_files()
    return jsonify(files)

@app.route('/api/upload', methods=['POST'])
def api_upload():
    """Upload a new media file"""
    if 'file' not in request.files:
        return jsonify({'success': False, 'message': 'No file provided'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'success': False, 'message': 'No file selected'}), 400
    
    try:
        filename = secure_filename(file.filename)
        filepath = os.path.join(config['media_dir'], filename)
        file.save(filepath)
        return jsonify({'success': True, 'message': f'File {filename} uploaded successfully'})
    except RequestEntityTooLarge:
        return jsonify({'success': False, 'message': 'File too large (max 2GB)'}), 413
    except Exception as e:
        logger.error(f"Error uploading file: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/files/<filename>', methods=['DELETE'])
def api_delete_file(filename):
    """Delete a media file"""
    filepath = os.path.join(config['media_dir'], secure_filename(filename))
    
    if os.path.exists(filepath):
        try:
            os.remove(filepath)
            return jsonify({'success': True, 'message': f'File {filename} deleted'})
        except Exception as e:
            logger.error(f"Error deleting file: {e}")
            return jsonify({'success': False, 'message': str(e)}), 500
    else:
        return jsonify({'success': False, 'message': 'File not found'}), 404

@app.route('/api/sync/master', methods=['POST'])
def api_sync_master():
    """Set device as sync master"""
    config['sync_mode'] = 'master'
    config['master_ip'] = ''
    save_config()
    
    # Restart sync manager in master mode
    global sync_manager
    if sync_manager:
        sync_manager.stop()
    sync_manager = SyncManager(mode='master', config=config)
    sync_manager.start()
    
    return jsonify({'success': True, 'message': 'Device set as sync master'})

@app.route('/api/sync/slave', methods=['POST'])
def api_sync_slave():
    """Set device as sync slave"""
    data = request.get_json() or {}
    master_ip = data.get('master_ip')
    
    if not master_ip:
        return jsonify({'success': False, 'message': 'Master IP required'}), 400
    
    config['sync_mode'] = 'slave'
    config['master_ip'] = master_ip
    save_config()
    
    # Restart sync manager in slave mode
    global sync_manager
    if sync_manager:
        sync_manager.stop()
    sync_manager = SyncManager(mode='slave', config=config, player=player)
    sync_manager.start()
    
    return jsonify({'success': True, 'message': f'Device set as sync slave to {master_ip}'})

@app.route('/api/sync/standalone', methods=['POST'])
def api_sync_standalone():
    """Set device to standalone mode"""
    config['sync_mode'] = 'standalone'
    config['master_ip'] = ''
    save_config()
    
    # Stop sync manager
    global sync_manager
    if sync_manager:
        sync_manager.stop()
        sync_manager = None
    
    return jsonify({'success': True, 'message': 'Device set to standalone mode'})

@app.route('/api/health', methods=['GET'])
def api_health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'uptime': time.time() - start_time
    })

# Static file serving
@app.route('/static/<path:filename>')
def serve_static(filename):
    """Serve static files"""
    return send_from_directory('static', filename)

# Initialize application
def initialize():
    """Initialize the application"""
    global player, sync_manager, start_time
    
    start_time = time.time()
    
    # Load configuration
    load_config()
    
    # Create media directory if it doesn't exist
    os.makedirs(config['media_dir'], exist_ok=True)
    
    # Initialize player
    player = MPVController(config)
    
    # Initialize sync manager if needed
    if config.get('sync_mode') == 'master':
        sync_manager = SyncManager(mode='master', config=config, player=player)
        sync_manager.start()
        logger.info("Sync manager started in MASTER mode")
    elif config.get('sync_mode') == 'slave':
        sync_manager = SyncManager(mode='slave', config=config, player=player)
        sync_manager.start()
        logger.info(f"Sync manager started in SLAVE mode, connecting to {config.get('master_ip')}")
    else:
        logger.info("Running in standalone mode (no sync)")
    
    logger.info("MPV Pi Player initialized successfully")

if __name__ == '__main__':
    initialize()
    port = config.get('port', 8080)
    app.run(host='0.0.0.0', port=port, debug=False)
