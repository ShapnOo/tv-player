/**
 * Shapno Custom Video Theater Player
 * Optimized for Smart TVs, Mobile, and Desktop Browsers
 * High-performance Range Seeking, Lossless Transmuxing, Subtitles & TV Remote Support
 */

class ShapnoPlayer {
  constructor() {
    this.overlay = document.getElementById('playerOverlay');
    this.video = document.getElementById('mainVideo');
    this.videoContainer = document.getElementById('videoContainer');
    this.titleEl = document.getElementById('playerTitle');
    this.subtitleEl = document.getElementById('playerSubtitle');
    this.controls = document.getElementById('customControls');
    this.playIndicator = document.getElementById('playIndicator');

    // Controls
    this.btnPlayPause = document.getElementById('btnPlayPause');
    this.ctrlPlayIcon = document.getElementById('ctrlPlayIcon');
    this.ctrlPauseIcon = document.getElementById('ctrlPauseIcon');
    this.btnRewind = document.getElementById('btnRewind');
    this.btnForward = document.getElementById('btnForward');
    this.btnMute = document.getElementById('btnMute');
    this.ctrlVolumeHigh = document.getElementById('ctrlVolumeHigh');
    this.ctrlVolumeMuted = document.getElementById('ctrlVolumeMuted');
    this.volumeSlider = document.getElementById('volumeSlider');
    this.currentTimeEl = document.getElementById('currentTime');
    this.durationTimeEl = document.getElementById('durationTime');

    // Scrubber
    this.progressContainer = document.getElementById('progressContainer');
    this.progressCurrent = document.getElementById('progressCurrent');
    this.progressBuffered = document.getElementById('progressBuffered');
    this.progressThumb = document.getElementById('progressThumb');
    this.timeTooltip = document.getElementById('timeTooltip');

    // Top & Extras
    this.btnClose = document.getElementById('btnClosePlayer');
    this.btnPip = document.getElementById('btnPip');
    this.btnFullscreen = document.getElementById('btnFullscreen');
    this.fsEnterIcon = document.getElementById('fsEnterIcon');
    this.fsExitIcon = document.getElementById('fsExitIcon');
    this.btnSubtitles = document.getElementById('btnSubtitles');
    this.subState = document.getElementById('subState');
    this.btnSpeed = document.getElementById('btnSpeed');
    this.speedMenu = document.getElementById('speedMenu');
    this.btnNextEp = document.getElementById('btnNextEpisode');

    // State
    this.currentItem = null;
    this.playlist = [];
    this.hideControlsTimer = null;
    this.subtitlesActive = false;
    this.currentSubtitleIndex = 0;
    this.isTransmuxing = false;

    // Enable AirPlay & TV features (and inline playback for iOS/WebKit)
    this.video.setAttribute('x-webkit-airplay', 'allow');
    this.video.setAttribute('webkit-playsinline', 'true');
    this.video.setAttribute('playsinline', 'true');
    this.video.playsInline = true;
    this.video.preload = 'auto';

    this.initEvents();
  }

  initEvents() {
    // Play / Pause toggle
    this.btnPlayPause.addEventListener('click', () => this.togglePlay());
    this.video.addEventListener('click', () => this.togglePlay());

    // 10s Skips
    this.btnRewind.addEventListener('click', () => this.seekBy(-10));
    this.btnForward.addEventListener('click', () => this.seekBy(10));

    // Volume
    this.volumeSlider.addEventListener('input', (e) => {
      this.video.volume = parseFloat(e.target.value);
      this.video.muted = (this.video.volume === 0);
      this.updateVolumeIcons();
    });

    this.btnMute.addEventListener('click', () => {
      this.video.muted = !this.video.muted;
      this.updateVolumeIcons();
    });

    // Video events
    this.video.addEventListener('timeupdate', () => this.onTimeUpdate());
    this.video.addEventListener('progress', () => this.onProgress());
    this.video.addEventListener('loadedmetadata', () => this.onMetadataLoaded());
    this.video.addEventListener('ended', () => this.onVideoEnded());
    this.video.addEventListener('play', () => this.onPlayStateChange(true));
    this.video.addEventListener('pause', () => this.onPlayStateChange(false));

    // Scrubber
    this.progressContainer.addEventListener('click', (e) => this.seekToEvent(e));
    this.progressContainer.addEventListener('mousemove', (e) => this.onScrubberHover(e));

    // Fullscreen & PiP
    this.btnFullscreen.addEventListener('click', () => this.toggleFullscreen());
    this.btnPip.addEventListener('click', () => this.togglePip());
    this.btnClose.addEventListener('click', () => this.close());

    // Subtitles
    this.btnSubtitles.addEventListener('click', () => this.toggleSubtitles());

    // Speed picker
    this.btnSpeed.addEventListener('click', (e) => {
      e.stopPropagation();
      this.speedMenu.classList.toggle('show');
    });

    document.querySelectorAll('.speed-item').forEach(item => {
      item.addEventListener('click', () => {
        const speed = parseFloat(item.dataset.speed);
        this.video.playbackRate = speed;
        this.btnSpeed.textContent = `${speed}x`;
        document.querySelectorAll('.speed-item').forEach(el => el.classList.remove('active'));
        item.classList.add('active');
        this.speedMenu.classList.remove('show');
      });
    });

    document.addEventListener('click', (e) => {
      if (!this.speedMenu.contains(e.target) && e.target !== this.btnSpeed) {
        this.speedMenu.classList.remove('show');
      }
    });

    // Next Episode
    this.btnNextEp.addEventListener('click', () => this.playNextEpisode());

    // User activity on TV/Mobile
    this.overlay.addEventListener('mousemove', () => this.showControlsTemporarily());
    this.overlay.addEventListener('touchstart', () => this.showControlsTemporarily(), { passive: true });

    // Universal TV Remote & Keyboard Shortcuts
    document.addEventListener('keydown', (e) => this.handleKeyNavigation(e));
  }

  handleKeyNavigation(e) {
    if (this.overlay.style.display === 'none') return;

    // TV Remote & Keyboard Event codes
    const key = e.key;
    const code = e.code;

    if (code === 'Space' || key === 'MediaPlayPause' || key === 'MediaPlay' || key === 'Play') {
      e.preventDefault();
      this.togglePlay();
    } else if (code === 'ArrowLeft' || key === 'MediaRewind' || key === 'Rewind') {
      e.preventDefault();
      this.seekBy(-10);
    } else if (code === 'ArrowRight' || key === 'MediaFastForward' || key === 'FastForward') {
      e.preventDefault();
      this.seekBy(10);
    } else if (code === 'ArrowUp') {
      e.preventDefault();
      this.video.volume = Math.min(1, this.video.volume + 0.1);
      this.volumeSlider.value = this.video.volume;
      this.updateVolumeIcons();
      this.showControlsTemporarily();
    } else if (code === 'ArrowDown') {
      e.preventDefault();
      this.video.volume = Math.max(0, this.video.volume - 0.1);
      this.volumeSlider.value = this.video.volume;
      this.updateVolumeIcons();
      this.showControlsTemporarily();
    } else if (code === 'KeyF' || key === 'ZoomToggle') {
      e.preventDefault();
      this.toggleFullscreen();
    } else if (code === 'KeyM') {
      e.preventDefault();
      this.video.muted = !this.video.muted;
      this.updateVolumeIcons();
    } else if (code === 'Escape' || key === 'Back' || key === 'BrowserBack' || key === 'GoBack') {
      e.preventDefault();
      this.close();
    }
  }

  play(item, playlist = []) {
    this.currentItem = item;
    this.playlist = playlist;
    this.overlay.style.display = 'flex';
    document.body.style.overflow = 'hidden';

    // Update titles
    this.titleEl.textContent = item.title;
    if (item.type === 'series') {
      const epLabel = `Season ${item.season || 1} • Episode ${item.episode || 1}`;
      this.subtitleEl.textContent = `${epLabel} • Direct Local Stream`;
    } else {
      this.subtitleEl.textContent = `${item.year ? item.year + ' • ' : ''}${item.format} • ${item.sizeFormatted}`;
    }

    // Check if next episode exists
    const nextEp = this.findNextEpisode();
    this.btnNextEp.style.display = nextEp ? 'inline-flex' : 'none';

    // Device / Browser Format Compatibility Check
    const ext = item.fileName.split('.').pop().toLowerCase();
    const canPlayMkv = (
      this.video.canPlayType('video/x-matroska') !== '' ||
      this.video.canPlayType('video/webm; codecs="vp8, vorbis"') !== ''
    );

    // If MKV on Safari / TV browser that lacks MKV container support, use real-time transmuxer
    if (ext === 'mkv' && !canPlayMkv) {
      this.isTransmuxing = true;
      this.subtitleEl.textContent += ' • ⚡ TV Hardware Stream';
      this.video.src = `/api/transmux/${item.id}`;
    } else {
      this.isTransmuxing = false;
      this.video.src = `/api/stream/${item.id}`;
    }

    // Reset and attach subtitles
    while (this.video.firstChild) {
      this.video.removeChild(this.video.firstChild);
    }

    if (item.hasSubtitles && item.subtitles.length > 0) {
      this.btnSubtitles.style.display = 'inline-flex';
      this.btnSubtitles.classList.add('active');
      this.subState.textContent = 'ON';
      this.subtitlesActive = true;

      item.subtitles.forEach((sub, idx) => {
        const track = document.createElement('track');
        track.kind = 'subtitles';
        track.label = sub.label || `Subtitles ${idx + 1}`;
        track.srclang = 'en';
        track.src = `/api/subtitles/${item.id}?index=${idx}`;
        if (idx === 0) track.default = true;
        this.video.appendChild(track);
      });
    } else {
      this.btnSubtitles.style.display = 'none';
      this.subtitlesActive = false;
    }

    // Restore saved progress
    const savedTime = localStorage.getItem(`cinedata_pos_${item.id}`);
    if (savedTime && parseFloat(savedTime) > 5) {
      this.video.currentTime = parseFloat(savedTime);
    }

    // Start playback
    const playPromise = this.video.play();
    if (playPromise !== undefined) {
      playPromise.catch(err => {
        console.log('[Player] Autoplay waiting for user gesture:', err.message);
      });
    }

    this.showControlsTemporarily();
  }

  togglePlay() {
    if (this.video.paused) {
      this.video.play();
      this.showIndicator('play');
    } else {
      this.video.pause();
      this.showIndicator('pause');
    }
  }

  onPlayStateChange(isPlaying) {
    if (isPlaying) {
      this.ctrlPlayIcon.style.display = 'none';
      this.ctrlPauseIcon.style.display = 'block';
      this.showControlsTemporarily();
    } else {
      this.ctrlPlayIcon.style.display = 'block';
      this.ctrlPauseIcon.style.display = 'none';
      this.overlay.classList.add('controls-visible');
      clearTimeout(this.hideControlsTimer);
    }
  }

  showIndicator(type) {
    this.playIndicator.classList.remove('animate');
    void this.playIndicator.offsetWidth;
    this.playIndicator.classList.add('animate');
  }

  seekBy(seconds) {
    const newTime = Math.max(0, Math.min(this.video.duration || 0, this.video.currentTime + seconds));
    this.video.currentTime = newTime;
    this.showControlsTemporarily();
  }

  seekToEvent(e) {
    const rect = this.progressContainer.getBoundingClientRect();
    const pos = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    const targetTime = pos * (this.video.duration || 0);
    if (!isNaN(targetTime)) {
      this.video.currentTime = targetTime;
    }
  }

  onScrubberHover(e) {
    const rect = this.progressContainer.getBoundingClientRect();
    const pos = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    const hoverTime = pos * (this.video.duration || 0);

    this.timeTooltip.style.left = `${pos * 100}%`;
    this.timeTooltip.textContent = this.formatTime(hoverTime);
  }

  onTimeUpdate() {
    const current = this.video.currentTime;
    const duration = this.video.duration || 0;

    this.currentTimeEl.textContent = this.formatTime(current);

    if (duration > 0) {
      const pct = (current / duration) * 100;
      this.progressCurrent.style.width = `${pct}%`;
      this.progressThumb.style.left = `${pct}%`;

      if (this.currentItem) {
        localStorage.setItem(`cinedata_pos_${this.currentItem.id}`, current.toString());
        localStorage.setItem(`cinedata_dur_${this.currentItem.id}`, duration.toString());

        // Sync with server progress API for cross-device continuation (TV + Web)
        const now = Date.now();
        if (!this._lastServerSync || (now - this._lastServerSync > 5000)) {
          this._lastServerSync = now;
          fetch(`/api/progress/${this.currentItem.id}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              pos: Math.round(current),
              dur: Math.round(duration),
              title: this.currentItem.cleanTitle || this.currentItem.title,
            }),
          }).catch(() => {});
        }
      }
    }
  }

  onProgress() {
    if (this.video.buffered.length > 0 && this.video.duration > 0) {
      const bufferedEnd = this.video.buffered.end(this.video.buffered.length - 1);
      const pct = (bufferedEnd / this.video.duration) * 100;
      this.progressBuffered.style.width = `${pct}%`;
    }
  }

  onMetadataLoaded() {
    this.durationTimeEl.textContent = this.formatTime(this.video.duration);
  }

  onVideoEnded() {
    const nextEp = this.findNextEpisode();
    if (nextEp) {
      this.play(nextEp, this.playlist);
    }
  }

  findNextEpisode() {
    if (!this.currentItem || this.currentItem.type !== 'series') return null;
    const currentIndex = this.playlist.findIndex(i => i.id === this.currentItem.id);
    if (currentIndex !== -1 && currentIndex + 1 < this.playlist.length) {
      const candidate = this.playlist[currentIndex + 1];
      if (candidate.type === 'series') return candidate;
    }
    return null;
  }

  playNextEpisode() {
    const nextEp = this.findNextEpisode();
    if (nextEp) {
      this.play(nextEp, this.playlist);
    }
  }

  toggleSubtitles() {
    if (!this.video.textTracks || this.video.textTracks.length === 0) return;
    const track = this.video.textTracks[0];

    if (this.subtitlesActive) {
      track.mode = 'disabled';
      this.subtitlesActive = false;
      this.subState.textContent = 'OFF';
      this.btnSubtitles.classList.remove('active');
    } else {
      track.mode = 'showing';
      this.subtitlesActive = true;
      this.subState.textContent = 'ON';
      this.btnSubtitles.classList.add('active');
    }
  }

  updateVolumeIcons() {
    if (this.video.muted || this.video.volume === 0) {
      this.ctrlVolumeHigh.style.display = 'none';
      this.ctrlVolumeMuted.style.display = 'block';
    } else {
      this.ctrlVolumeHigh.style.display = 'block';
      this.ctrlVolumeMuted.style.display = 'none';
    }
  }

  async toggleFullscreen() {
    try {
      if (!document.fullscreenElement) {
        await this.overlay.requestFullscreen();
        this.fsEnterIcon.style.display = 'none';
        this.fsExitIcon.style.display = 'block';
      } else {
        await document.exitFullscreen();
        this.fsEnterIcon.style.display = 'block';
        this.fsExitIcon.style.display = 'none';
      }
    } catch (e) {
      console.warn('Fullscreen toggle failed:', e);
    }
  }

  async togglePip() {
    try {
      if (document.pictureInPictureElement) {
        await document.exitPictureInPicture();
      } else if (document.pictureInPictureEnabled && this.video) {
        await this.video.requestPictureInPicture();
      }
    } catch (e) {
      console.warn('PiP failed:', e);
    }
  }

  showControlsTemporarily() {
    this.overlay.classList.add('controls-visible');
    clearTimeout(this.hideControlsTimer);

    if (!this.video.paused) {
      this.hideControlsTimer = setTimeout(() => {
        this.overlay.classList.remove('controls-visible');
      }, 3500);
    }
  }

  close() {
    this.video.pause();
    this.video.src = '';
    this.overlay.style.display = 'none';
    document.body.style.overflow = '';
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    }
    window.dispatchEvent(new CustomEvent('cinedata-closed'));
  }

  formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '00:00';
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);

    const mStr = String(mins).padStart(2, '0');
    const sStr = String(secs).padStart(2, '0');

    if (hrs > 0) {
      return `${hrs}:${mStr}:${sStr}`;
    }
    return `${mStr}:${sStr}`;
  }
}

// Global instance
window.playerInstance = new ShapnoPlayer();
