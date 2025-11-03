#!/usr/bin/env python3
"""
MPV Controller Module
Handles video playback using MPV with hardware acceleration for Raspberry Pi
"""

import os
import json
import time
import logging
import subprocess
import threading
import socket

logger = logging.getLogger(__name__)

class MPVController:
    """
    Controller for MPV player with IPC socket communication
    Optimized for Raspberry Pi 4 with hardware acceleration
    """
    
    def __init__(self, config):
        self.config = config
        self.current_file = None
        self.process = None
        self.state = 'stopped'
        self.position = 0
        self.duration = 0
        self.volume = config.get('volume', 100)
        
        # MPV IPC socket path
        self.mpv_socket = '/tmp/mpvsocket'
        
        # Start monitoring thread
        self.monitor_thread = threading.Thread(target=self._monitor_position, daemon=True)
        self.monitor_thread.start()
        
        logger.info("MPV controller initialized")
    
    def play(self, filepath):
        """Start playing a video file"""
        try:
            # Stop current playback if any
            self.stop()
            
            if not os.path.exists(filepath):
                logger.error(f"File not found: {filepath}")
                return False
            
            self.current_file = filepath
            
            # Build MPV command with hardware acceleration for Pi 4
            cmd = ['mpv']
            
            # Check if display is connected
            display_connected = self._check_display_connected()
            
            # Hardware acceleration settings for Raspberry Pi 4
            if display_connected:
                # Use hardware rendering when display is connected
                if self.config.get('hardware_accel', True):
                    cmd.extend([
                        '--hwdec=auto-copy',      # Auto hardware decoding
                        '--vo=drm',               # Direct rendering for console
                        '--drm-mode=1920x1080',   # Force 1080p output
                        '--drm-connector=HDMI-A-1', # Use HDMI-1
                    ])
                else:
                    cmd.extend([
                        '--vo=drm',  # Direct rendering without GPU
                        '--drm-mode=1920x1080',
                        '--drm-connector=HDMI-A-1',
                    ])
            else:
                # Use null output when no display (headless mode)
                logger.info("No display detected - running in headless mode")
                cmd.extend([
                    '--vo=null',              # Null video output (no display needed)
                    '--ao=null',               # Null audio output (optional, remove if you want audio)
                    '--no-video',              # Don't process video (faster in headless)
                ])
            
            # Display settings
            cmd.extend([
                '--fullscreen',
                '--no-border',
                '--no-osc',
                '--no-osd-bar',
                '--no-input-default-bindings',
                '--no-input-cursor',
                '--cursor-autohide=no',
                '--no-terminal',
                '--quiet',
                '--really-quiet',
            ])
            
            # Audio/Video settings
            cmd.extend([
                f'--volume={self.volume}',
                '--video-sync=display-resample',
                '--audio-channels=stereo',  # Force stereo output
                '--audio-device=alsa/hdmi:CARD=vc4hdmi0,DEV=0',  # Raspberry Pi 4 HDMI audio output
                '--audio-samplerate=48000',  # Standard HDMI sample rate
            ])
            
            # IPC socket for control
            cmd.extend([
                f'--input-ipc-server={self.mpv_socket}',
            ])
            
            # Add the file to play
            cmd.append(filepath)
            
            # Start MPV process
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL
            )
            
            self.state = 'playing'
            time.sleep(0.5)  # Give MPV time to start
            
            logger.info(f"MPV started playing: {filepath}")
            return True
            
        except Exception as e:
            logger.error(f"Error starting MPV: {e}")
            return False
    
    def _check_display_connected(self):
        """Check if HDMI display is connected"""
        try:
            # Check for HDMI connection on Raspberry Pi
            import subprocess
            result = subprocess.run(['tvservice', '-s'], capture_output=True, text=True, timeout=2)
            if result.returncode == 0 and 'HDMI' in result.stdout:
                return True
            
            # Alternative check using /sys/class/drm
            import glob
            for card_path in glob.glob('/sys/class/drm/card*-HDMI-*/status'):
                try:
                    with open(card_path, 'r') as f:
                        if 'connected' in f.read():
                            return True
                except:
                    continue
            
            return False
        except:
            # If we can't detect, assume display is connected
            return True
    
    def pause(self):
        """Toggle pause/resume"""
        try:
            if self._send_command(['cycle', 'pause']):
                if self.state == 'playing':
                    self.state = 'paused'
                elif self.state == 'paused':
                    self.state = 'playing'
                return True
            return False
        except Exception as e:
            logger.error(f"Error toggling pause: {e}")
            return False
    
    def resume(self):
        """Resume playback if paused"""
        if self.state == 'paused':
            return self.pause()
        return True
    
    def stop(self):
        """Stop playback"""
        try:
            # Send quit command to MPV
            self._send_command(['quit'])
            
            # Terminate process if still running
            if self.process and self.process.poll() is None:
                self.process.terminate()
                time.sleep(0.5)
                if self.process.poll() is None:
                    self.process.kill()
            
            self.process = None
            self.state = 'stopped'
            self.current_file = None
            self.position = 0
            self.duration = 0
            
            # Clean up socket
            if os.path.exists(self.mpv_socket):
                try:
                    os.remove(self.mpv_socket)
                except:
                    pass
            
            logger.info("Playback stopped")
            return True
            
        except Exception as e:
            logger.error(f"Error stopping playback: {e}")
            return False
    
    def seek(self, position):
        """Seek to specific position in seconds"""
        try:
            if self._send_command(['seek', position, 'absolute']):
                self.position = position
                return True
            return False
        except Exception as e:
            logger.error(f"Error seeking: {e}")
            return False
    
    def set_volume(self, level):
        """Set volume level (0-100)"""
        try:
            self.volume = max(0, min(100, level))
            if self._send_command(['set_property', 'volume', self.volume]):
                return True
            return False
        except Exception as e:
            logger.error(f"Error setting volume: {e}")
            return False
    
    def get_state(self):
        """Get current player state"""
        # Check if process is still running
        if self.process and self.process.poll() is not None:
            self.state = 'stopped'
            self.current_file = None
        
        return self.state
    
    def get_position(self):
        """Get current playback position in seconds"""
        return self.position
    
    def get_duration(self):
        """Get media duration in seconds"""
        return self.duration
    
    def get_volume(self):
        """Get current volume level"""
        return self.volume
    
    def set_playback_speed(self, speed):
        """Set playback speed for synchronization (1.0 = normal)"""
        try:
            return self._send_command(['set_property', 'speed', speed])
        except:
            return False
    
    def _send_command(self, command):
        """Send command to MPV via IPC socket"""
        try:
            if not os.path.exists(self.mpv_socket):
                return False
            
            # Create socket connection
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(1.0)
            sock.connect(self.mpv_socket)
            
            # Send command as JSON
            cmd_json = json.dumps({'command': command}) + '\n'
            sock.send(cmd_json.encode('utf-8'))
            
            # Read response
            response = b''
            while True:
                data = sock.recv(4096)
                if not data:
                    break
                response += data
                if b'\n' in response:
                    break
            
            sock.close()
            
            # Parse response
            if response:
                result = json.loads(response.decode('utf-8').strip())
                return result.get('error') == 'success'
            
            return False
            
        except Exception as e:
            logger.debug(f"IPC command failed: {e}")
            return False
    
    def _get_property(self, property_name):
        """Get property value from MPV"""
        try:
            if not os.path.exists(self.mpv_socket):
                return None
            
            # Create socket connection
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(0.5)
            sock.connect(self.mpv_socket)
            
            # Send command
            cmd_json = json.dumps({'command': ['get_property', property_name]}) + '\n'
            sock.send(cmd_json.encode('utf-8'))
            
            # Read response
            response = b''
            while True:
                data = sock.recv(4096)
                if not data:
                    break
                response += data
                if b'\n' in response:
                    break
            
            sock.close()
            
            # Parse response
            if response:
                result = json.loads(response.decode('utf-8').strip())
                if result.get('error') == 'success':
                    return result.get('data')
            
            return None
            
        except:
            return None
    
    def _monitor_position(self):
        """Monitor playback position in background"""
        while True:
            try:
                if self.state == 'playing':
                    # Update position
                    pos = self._get_property('time-pos')
                    if pos is not None:
                        self.position = float(pos)
                    
                    # Update duration
                    dur = self._get_property('duration')
                    if dur is not None:
                        self.duration = float(dur)
                    
                    # Check if playback ended
                    if self.duration > 0 and self.position >= self.duration - 1:
                        # Handle loop if enabled
                        if self.config.get('loop', False):
                            self.seek(0)
                        else:
                            self.state = 'stopped'
                            
            except Exception as e:
                logger.debug(f"Monitor error: {e}")
            
            time.sleep(0.5)

