// MPV Pi Player - Frontend JavaScript (No Sync Version)

let currentStatus = {};
let statusInterval = null;

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    initializeEventListeners();
    loadFiles();
    startStatusPolling();
    updateApiEndpoint();
});

// Initialize all event listeners
function initializeEventListeners() {
    // Player controls
    document.getElementById('btn-play').addEventListener('click', handlePlay);
    document.getElementById('btn-pause').addEventListener('click', handlePause);
    document.getElementById('btn-stop').addEventListener('click', handleStop);
    document.getElementById('btn-skip-back').addEventListener('click', () => handleSkip(-30));
    document.getElementById('btn-skip-forward').addEventListener('click', () => handleSkip(30));
    document.getElementById('btn-seek').addEventListener('click', handleSeek);
    
    // Progress bar click to seek
    document.getElementById('progress-bar').addEventListener('click', handleProgressClick);
    
    // Volume control
    const volumeSlider = document.getElementById('volume');
    volumeSlider.addEventListener('change', handleVolumeChange);
    volumeSlider.addEventListener('input', function() {
        document.getElementById('volume-value').textContent = this.value + '%';
    });
    
    // File management
    document.getElementById('btn-browse').addEventListener('click', () => {
        document.getElementById('fileInput').click();
    });
    document.getElementById('fileInput').addEventListener('change', handleFileUpload);
    
    // Drag and drop
    const uploadArea = document.getElementById('upload-area');
    uploadArea.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadArea.classList.add('dragover');
    });
    uploadArea.addEventListener('dragleave', () => {
        uploadArea.classList.remove('dragover');
    });
    uploadArea.addEventListener('drop', handleFileDrop);
}

// Start polling for status updates
function startStatusPolling() {
    statusInterval = setInterval(updateStatus, 1000);
    updateStatus(); // Initial update
}

// Update player status
async function updateStatus() {
    try {
        const response = await fetch('/api/status');
        const status = await response.json();
        currentStatus = status;
        
        // Update UI elements
        document.getElementById('hostname').textContent = status.hostname || 'Unknown';
        
        // Update current file
        if (status.current_file) {
            const filename = status.current_file.split('/').pop();
            document.getElementById('current-file').textContent = filename;
        } else {
            document.getElementById('current-file').textContent = 'No file selected';
        }
        
        // Update progress bar
        if (status.duration > 0) {
            const progressPercent = (status.position / status.duration) * 100;
            document.getElementById('progress-fill').style.width = progressPercent + '%';
            document.getElementById('current-time').textContent = formatTime(status.position);
            document.getElementById('duration').textContent = formatTime(status.duration);
        } else {
            document.getElementById('progress-fill').style.width = '0%';
            document.getElementById('current-time').textContent = '00:00';
            document.getElementById('duration').textContent = '00:00';
        }
        
        // Update status display
        document.getElementById('player-state').textContent = status.state.charAt(0).toUpperCase() + status.state.slice(1);
        document.getElementById('position-display').textContent = Math.floor(status.position) + 's';
        document.getElementById('volume-display').textContent = status.volume + '%';
        
        // Update volume slider
        document.getElementById('volume').value = status.volume;
        document.getElementById('volume-value').textContent = status.volume + '%';
        
    } catch (error) {
        console.error('Failed to update status:', error);
    }
}

// Player control handlers
async function handlePlay() {
    try {
        const response = await fetch('/api/play', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        const result = await response.json();
        if (result.success) {
            showNotification('Playback started', 'success');
        }
    } catch (error) {
        showNotification('Failed to start playback', 'error');
    }
}

async function handlePause() {
    try {
        const response = await fetch('/api/pause', {
            method: 'POST'
        });
        const result = await response.json();
        if (result.success) {
            showNotification('Playback toggled', 'success');
        }
    } catch (error) {
        showNotification('Failed to pause', 'error');
    }
}

async function handleStop() {
    try {
        const response = await fetch('/api/stop', {
            method: 'POST'
        });
        const result = await response.json();
        if (result.success) {
            showNotification('Playback stopped', 'success');
        }
    } catch (error) {
        showNotification('Failed to stop', 'error');
    }
}

async function handleSkip(seconds) {
    try {
        const response = await fetch('/api/skip', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ seconds: seconds })
        });
        const result = await response.json();
        if (result.success) {
            showNotification(`Skipped ${seconds}s`, 'success');
        }
    } catch (error) {
        showNotification('Failed to skip', 'error');
    }
}

async function handleSeek() {
    const position = document.getElementById('seek-position').value;
    if (!position) return;
    
    try {
        const response = await fetch('/api/seek', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ position: parseInt(position) })
        });
        const result = await response.json();
        if (result.success) {
            showNotification(`Seeked to ${position}s`, 'success');
            document.getElementById('seek-position').value = '';
        }
    } catch (error) {
        showNotification('Failed to seek', 'error');
    }
}

async function handleProgressClick(event) {
    if (currentStatus.duration <= 0) return;
    
    const rect = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const clickPercent = (x / rect.width);
    const seekPosition = clickPercent * currentStatus.duration;
    
    try {
        const response = await fetch('/api/seek', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ position: Math.floor(seekPosition) })
        });
        const result = await response.json();
        if (result.success) {
            showNotification(`Seeked to ${Math.floor(seekPosition)}s`, 'success');
        }
    } catch (error) {
        showNotification('Failed to seek', 'error');
    }
}

async function handleVolumeChange(event) {
    const level = event.target.value;
    try {
        const response = await fetch('/api/volume', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ level: parseInt(level) })
        });
        const result = await response.json();
        if (result.success) {
            showNotification(`Volume set to ${level}%`, 'success');
        }
    } catch (error) {
        showNotification('Failed to set volume', 'error');
    }
}

// File management
async function loadFiles() {
    try {
        const response = await fetch('/api/files');
        const files = await response.json();
        
        const fileList = document.getElementById('file-list');
        fileList.innerHTML = '';
        
        if (files.length === 0) {
            fileList.innerHTML = '<div style="padding: 20px; text-align: center; color: rgba(255,255,255,0.5);">No files uploaded</div>';
            return;
        }
        
        files.forEach(file => {
            const fileItem = document.createElement('div');
            fileItem.className = 'file-item';
            fileItem.innerHTML = `
                <div class="file-name">${file.name}</div>
                <div class="file-size">${formatFileSize(file.size)}</div>
                <div class="file-actions">
                    <button class="btn btn-primary" style="padding: 6px 12px; font-size: 14px;" onclick="playFile('${file.name}')">PLAY</button>
                    <button class="btn btn-danger" style="padding: 6px 12px; font-size: 14px;" onclick="deleteFile('${file.name}')">DELETE</button>
                </div>
            `;
            fileList.appendChild(fileItem);
        });
    } catch (error) {
        showNotification('Failed to load files', 'error');
    }
}

async function playFile(filename) {
    try {
        const response = await fetch('/api/play', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ file: filename })
        });
        const result = await response.json();
        if (result.success) {
            showNotification(`Playing ${filename}`, 'success');
        }
    } catch (error) {
        showNotification('Failed to play file', 'error');
    }
}

async function deleteFile(filename) {
    if (!confirm(`Delete ${filename}?`)) return;
    
    try {
        const response = await fetch(`/api/files/${filename}`, {
            method: 'DELETE'
        });
        const result = await response.json();
        if (result.success) {
            showNotification(`${filename} deleted`, 'success');
            loadFiles();
        }
    } catch (error) {
        showNotification('Failed to delete file', 'error');
    }
}

function handleFileDrop(event) {
    event.preventDefault();
    event.currentTarget.classList.remove('dragover');
    
    const files = event.dataTransfer.files;
    if (files.length > 0) {
        uploadFile(files[0]);
    }
}

async function handleFileUpload(event) {
    const file = event.target.files[0];
    if (!file) return;
    uploadFile(file);
}

async function uploadFile(file) {
    const formData = new FormData();
    formData.append('file', file);
    
    const progressDiv = document.getElementById('upload-progress');
    const progressFill = document.getElementById('upload-progress-fill');
    const statusText = document.getElementById('upload-status');
    
    progressDiv.style.display = 'block';
    statusText.textContent = `Uploading ${file.name}...`;
    
    try {
        const xhr = new XMLHttpRequest();
        
        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                const percentComplete = (e.loaded / e.total) * 100;
                progressFill.style.width = percentComplete + '%';
                statusText.textContent = `Uploading ${file.name}... ${Math.round(percentComplete)}%`;
            }
        });
        
        xhr.addEventListener('load', () => {
            if (xhr.status === 200) {
                showNotification('File uploaded successfully', 'success');
                loadFiles();
                progressDiv.style.display = 'none';
                document.getElementById('fileInput').value = '';
            } else {
                showNotification('Upload failed', 'error');
                progressDiv.style.display = 'none';
            }
        });
        
        xhr.addEventListener('error', () => {
            showNotification('Upload failed', 'error');
            progressDiv.style.display = 'none';
        });
        
        xhr.open('POST', '/api/upload');
        xhr.send(formData);
        
    } catch (error) {
        showNotification('Upload failed', 'error');
        progressDiv.style.display = 'none';
    }
}

// Helper functions
function formatTime(seconds) {
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

function formatFileSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
}

function updateApiEndpoint() {
    const hostname = window.location.hostname;
    const port = window.location.port || '8080';
    document.getElementById('api-endpoint').textContent = `http://${hostname}:${port}/api`;
}

function showNotification(message, type) {
    // Create toast notification
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: ${type === 'success' ? '#4caf50' : '#f44336'};
        color: white;
        padding: 12px 20px;
        border-radius: 4px;
        box-shadow: 0 2px 5px rgba(0,0,0,0.3);
        z-index: 1000;
        transition: opacity 0.3s;
    `;
    document.body.appendChild(toast);
    
    // Remove after 3 seconds
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => {
            document.body.removeChild(toast);
        }, 300);
    }, 3000);
}

// Make functions globally available for inline onclick handlers
window.playFile = playFile;
window.deleteFile = deleteFile;

