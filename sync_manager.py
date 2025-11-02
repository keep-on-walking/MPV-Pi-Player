#!/usr/bin/env python3
"""
Synchronization Manager Module
Handles multi-player synchronization for master/slave configurations using WebSockets
"""

import json
import time
import logging
import threading
import asyncio
import websockets
from websockets.server import serve
import os

logger = logging.getLogger(__name__)

class SyncManager:
    """
    Manages synchronization between multiple video players
    Uses WebSocket for real-time communication
    """
    
    def __init__(self, mode='standalone', config=None, player=None):
        self.mode = mode  # 'master', 'slave', or 'standalone'
        self.config = config or {}
        self.player = player
        self.running = False
        self.sync_thread = None
        self.websocket_server = None
        self.connected_slaves = set()
        self.master_connection = None
        self.last_sync_time = 0
        self.sync_interval = 0.5  # seconds
        
        logger.info(f"Sync manager initialized in {mode} mode")
    
    def start(self):
        """Start synchronization"""
        if self.running:
            return
        
        self.running = True
        
        if self.mode == 'master':
            self.sync_thread = threading.Thread(target=self._run_master, daemon=True)
        elif self.mode == 'slave':
            self.sync_thread = threading.Thread(target=self._run_slave, daemon=True)
        else:
            return  # No sync in standalone mode
        
        self.sync_thread.start()
        logger.info(f"Sync manager started in {self.mode} mode")
    
    def stop(self):
        """Stop synchronization"""
        self.running = False
        
        if self.sync_thread:
            self.sync_thread.join(timeout=2)
            self.sync_thread = None
        
        logger.info("Sync manager stopped")
    
    def _run_master(self):
        """Run as sync master"""
        asyncio.set_event_loop(asyncio.new_event_loop())
        loop = asyncio.get_event_loop()
        
        # Start WebSocket server
        port = self.config.get('sync_port', 8765)
        
        async def start_server():
            self.websocket_server = await serve(
                self._handle_slave_connection, 
                "0.0.0.0", 
                port
            )
            logger.info(f"Master sync server started on port {port}")
            
            # Start broadcasting state
            asyncio.create_task(self._broadcast_master_state())
            
            await asyncio.Future()  # Run forever
        
        try:
            loop.run_until_complete(start_server())
        except Exception as e:
            logger.error(f"Master sync error: {e}")
    
    async def _handle_slave_connection(self, websocket, path):
        """Handle new slave connection"""
        self.connected_slaves.add(websocket)
        slave_ip = websocket.remote_address[0]
        logger.info(f"Slave connected from {slave_ip}")
        
        try:
            # Send initial state to new slave
            if self.player:
                state = self._get_player_state()
                await websocket.send(json.dumps({
                    'type': 'sync',
                    'data': state
                }))
            
            # Keep connection alive
            async for message in websocket:
                # Process any messages from slave (heartbeats, etc.)
                try:
                    data = json.loads(message)
                    if data.get('type') == 'heartbeat':
                        await websocket.pong()
                except:
                    pass
                    
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.connected_slaves.remove(websocket)
            logger.info(f"Slave disconnected from {slave_ip}")
    
    async def _broadcast_master_state(self):
        """Broadcast master state to all slaves"""
        while self.running:
            try:
                if self.connected_slaves and self.player:
                    state = self._get_player_state()
                    
                    # Only broadcast if playing
                    if state['state'] == 'playing':
                        message = json.dumps({
                            'type': 'sync',
                            'data': state
                        })
                        
                        # Send to all connected slaves
                        disconnected = set()
                        for slave in self.connected_slaves:
                            try:
                                await slave.send(message)
                            except:
                                disconnected.add(slave)
                        
                        # Remove disconnected slaves
                        self.connected_slaves.difference_update(disconnected)
                
                await asyncio.sleep(self.sync_interval)
            except Exception as e:
                logger.error(f"Error broadcasting state: {e}")
                await asyncio.sleep(1)
    
    def _run_slave(self):
        """Run as sync slave"""
        asyncio.set_event_loop(asyncio.new_event_loop())
        loop = asyncio.get_event_loop()
        loop.run_until_complete(self._connect_to_master())
    
    async def _connect_to_master(self):
        """Connect to master and sync"""
        master_ip = self.config.get('master_ip')
        port = self.config.get('sync_port', 8765)
        
        if not master_ip:
            logger.error("No master IP configured")
            return
        
        uri = f"ws://{master_ip}:{port}"
        
        while self.running:
            try:
                async with websockets.connect(uri) as websocket:
                    self.master_connection = websocket
                    logger.info(f"Connected to master at {master_ip}")
                    
                    # Listen for sync messages
                    while self.running:
                        try:
                            message = await asyncio.wait_for(
                                websocket.recv(), 
                                timeout=5.0
                            )
                            
                            data = json.loads(message)
                            if data['type'] == 'sync':
                                await self._apply_sync_state(data['data'])
                            elif data['type'] == 'command':
                                await self._execute_command(data['data'])
                        
                        except asyncio.TimeoutError:
                            # Send heartbeat
                            await websocket.send(json.dumps({'type': 'heartbeat'}))
                        except Exception as e:
                            logger.error(f"Error receiving sync message: {e}")
                            break
            
            except Exception as e:
                logger.error(f"Failed to connect to master: {e}")
                self.master_connection = None
                
                # Retry connection after delay
                if self.running:
                    await asyncio.sleep(5)
    
    async def _apply_sync_state(self, state):
        """Apply sync state from master"""
        if not self.player:
            return
        
        try:
            # Check if we need to play a different file
            master_file = state.get('current_file')
            if master_file and master_file != self.player.current_file:
                # Extract filename from path
                filename = os.path.basename(master_file)
                local_path = os.path.join(self.config['media_dir'], filename)
                
                if os.path.exists(local_path):
                    self.player.play(local_path)
                else:
                    logger.warning(f"File not found locally: {filename}")
                    return
            
            # Sync playback state
            master_state = state.get('state', 'stopped')
            slave_state = self.player.get_state()
            
            if master_state == 'playing' and slave_state != 'playing':
                self.player.resume()
            elif master_state == 'paused' and slave_state != 'paused':
                self.player.pause()
            elif master_state == 'stopped' and slave_state != 'stopped':
                self.player.stop()
            
            # Sync position with tolerance
            if master_state == 'playing':
                master_pos = state.get('position', 0)
                slave_pos = self.player.get_position()
                
                # Calculate drift
                drift = abs(master_pos - slave_pos)
                
                # If drift is more than 1 second, resync
                if drift > 1.0:
                    # Adjust for network latency
                    target_pos = master_pos + 0.2  # Add 200ms for latency
                    self.player.seek(target_pos)
                    logger.info(f"Resynced position: {slave_pos} -> {target_pos}")
                
                # Fine-tune playback speed if drift is between 0.2 and 1 second
                elif drift > 0.2:
                    if slave_pos < master_pos:
                        # We're behind, speed up slightly
                        self.player.set_playback_speed(1.05)
                    else:
                        # We're ahead, slow down slightly
                        self.player.set_playback_speed(0.95)
                else:
                    # Reset to normal speed
                    self.player.set_playback_speed(1.0)
            
            # Sync volume
            master_volume = state.get('volume', 100)
            if abs(master_volume - self.player.get_volume()) > 5:
                self.player.set_volume(master_volume)
        
        except Exception as e:
            logger.error(f"Error applying sync state: {e}")
    
    async def _execute_command(self, command):
        """Execute command from master"""
        if not self.player:
            return
        
        try:
            cmd_type = command.get('command')
            
            if cmd_type == 'play':
                filename = command.get('file')
                if filename:
                    filepath = os.path.join(self.config['media_dir'], filename)
                    self.player.play(filepath)
            
            elif cmd_type == 'pause':
                self.player.pause()
            
            elif cmd_type == 'resume':
                self.player.resume()
            
            elif cmd_type == 'stop':
                self.player.stop()
            
            elif cmd_type == 'seek':
                position = command.get('position', 0)
                self.player.seek(position)
            
            logger.info(f"Executed command: {cmd_type}")
        
        except Exception as e:
            logger.error(f"Error executing command: {e}")
    
    def _get_player_state(self):
        """Get current player state"""
        if not self.player:
            return {}
        
        return {
            'state': self.player.get_state(),
            'current_file': self.player.current_file,
            'position': self.player.get_position(),
            'duration': self.player.get_duration(),
            'volume': self.player.get_volume(),
            'timestamp': time.time()
        }
    
    def broadcast_command(self, command, data):
        """Broadcast command to slaves (called by master)"""
        if self.mode != 'master' or not self.connected_slaves:
            return
        
        message = json.dumps({
            'type': 'command',
            'data': {
                'command': command,
                **data
            }
        })
        
        # Send to all slaves asynchronously
        async def send_to_slaves():
            disconnected = set()
            for slave in self.connected_slaves:
                try:
                    await slave.send(message)
                except:
                    disconnected.add(slave)
            
            self.connected_slaves.difference_update(disconnected)
        
        # Run in event loop if available
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                asyncio.create_task(send_to_slaves())
        except:
            pass
