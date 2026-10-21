/**
 * Shapno Netflix-Style Series Explorer Page
 * Live Looping Random Episode Billboard Banner, Audio Toggle,
 * Beautiful Netflix Episode Grid & Smart TV D-Pad Remote Navigation.
 */

(function () {
  let series = null;
  let activePreviewEpisode = null;
  let isAudioMuted = true;

  // DOM Elements - Billboard
  const billboardPoster = document.getElementById('billboardPoster');
  const billboardVideo = document.getElementById('billboardVideo');
  if (billboardVideo) {
    billboardVideo.playsInline = true;
    billboardVideo.setAttribute('playsinline', '');
    billboardVideo.setAttribute('webkit-playsinline', 'true');
  }
  const seriesPageTitle = document.getElementById('seriesPageTitle');
  const seriesFolderSubtitle = document.getElementById('seriesFolderSubtitle');
  const billboardSeasonCount = document.getElementById('billboardSeasonCount');
  const billboardEpisodeCount = document.getElementById('billboardEpisodeCount');
  const billboardTotalSize = document.getElementById('billboardTotalSize');
  const previewChipText = document.getElementById('previewChipText');
  const btnPlayFirstEp = document.getElementById('btnPlayFirstEp');
  const playFirstText = document.getElementById('playFirstText');
  const btnResumeSeries = document.getElementById('btnResumeSeries');
  const resumeEpText = document.getElementById('resumeEpText');
  const btnToggleAudio = document.getElementById('btnToggleAudio');
  const iconAudioMuted = document.getElementById('iconAudioMuted');
  const iconAudioPlaying = document.getElementById('iconAudioPlaying');
  const audioText = document.getElementById('audioText');
  const btnShufflePreview = document.getElementById('btnShufflePreview');

  // Episodes Grid
  const episodesTotalBadge = document.getElementById('episodesTotalBadge');
  const netflixEpisodesGrid = document.getElementById('netflixEpisodesGrid');

  // Connect Modal
  const btnConnect = document.getElementById('btnConnect');
  const connectModal = document.getElementById('connectModal');
  const closeConnectModal = document.getElementById('closeConnectModal');
  const modalQrImage = document.getElementById('modalQrImage');
  const serverUrlInput = document.getElementById('serverUrlInput');
  const btnCopyUrl = document.getElementById('btnCopyUrl');
  const copyText = document.getElementById('copyText');
  const toast = document.getElementById('toast');

  // Initialize
  async function init() {
    setupEventListeners();
    await loadServerInfo();
    await loadSeriesDetails();
  }

  function getSeriesIdFromUrl() {
    const params = new URLSearchParams(window.location.search);
    if (params.get('id')) return params.get('id');

    // Check path /series/:id
    const parts = window.location.pathname.split('/').filter(Boolean);
    if (parts.length >= 2 && parts[0] === 'series') {
      return parts[1];
    }
    return null;
  }

  async function loadSeriesDetails() {
    const seriesId = getSeriesIdFromUrl();
    if (!seriesId) {
      showToast('No series specified. Redirecting...');
      setTimeout(() => { window.location.href = '/'; }, 1500);
      return;
    }

    try {
      const res = await fetch(`/api/series/${seriesId}`);
      if (!res.ok) throw new Error('Series not found');
      series = await res.json();

      document.title = `${series.title} • Shapno TV`;

      // Set Billboard details (Folder name is strictly Series Title!)
      seriesPageTitle.textContent = series.title;
      seriesFolderSubtitle.textContent = `Folder: Media/Series/${series.folderName}`;

      const seasonsSet = new Set(series.episodes.map(ep => ep.season || 1));
      const seasonsCount = seasonsSet.size;
      billboardSeasonCount.textContent = `${seasonsCount} Season${seasonsCount > 1 ? 's' : ''}`;
      billboardEpisodeCount.textContent = `${series.episodesCount} Episodes`;
      billboardTotalSize.textContent = series.totalSizeFormatted;
      episodesTotalBadge.textContent = `${series.episodesCount} Episode${series.episodesCount === 1 ? '' : 's'}`;

      // Start the live random episode billboard preview loop!
      startRandomPreview();

      // Check for saved progress across episodes to show Resume button
      checkResumeProgress();

      // Render Netflix-style episode cards
      renderEpisodes();
    } catch (err) {
      console.error('Failed to load series details:', err);
      showToast('Error loading TV series');
    }
  }

  /**
   * Billboard Random Preview Loop:
   * "where banner e random epidsode as banner cholte thakbe!"
   * Picks a random episode and plays it as a live looping video banner with dark gradients.
   */
  function startRandomPreview(preferredEp = null) {
    if (!series || !series.episodes || series.episodes.length === 0) return;

    if (preferredEp) {
      activePreviewEpisode = preferredEp;
    } else {
      const randIdx = Math.floor(Math.random() * series.episodes.length);
      activePreviewEpisode = series.episodes[randIdx];
    }

    // Set high-res scene poster immediately
    billboardPoster.style.backgroundImage = `url('/api/thumbnail/${activePreviewEpisode.id}')`;
    previewChipText.textContent = `Previewing: Season ${activePreviewEpisode.season || 1} • Episode ${activePreviewEpisode.episode || 1}`;

    // Browser format compatibility check
    const ext = activePreviewEpisode.fileName.split('.').pop().toLowerCase();
    const canPlayMkv = (
      billboardVideo.canPlayType('video/x-matroska') !== '' ||
      billboardVideo.canPlayType('video/webm; codecs="vp8, vorbis"') !== ''
    );

    const streamSrc = (ext === 'mkv' && !canPlayMkv)
      ? `/api/transmux/${activePreviewEpisode.id}`
      : `/api/stream/${activePreviewEpisode.id}`;

    billboardVideo.classList.remove('loaded');
    billboardVideo.src = streamSrc;
    billboardVideo.muted = isAudioMuted;

    // Start 30 seconds into the episode to skip studio intro and showcase real scenes
    const onLoadedMetadata = () => {
      const seekTime = Math.min(45, (billboardVideo.duration || 100) * 0.15);
      billboardVideo.currentTime = seekTime;
    };
    billboardVideo.addEventListener('loadedmetadata', onLoadedMetadata, { once: true });

    billboardVideo.play().then(() => {
      billboardVideo.classList.add('loaded');
    }).catch(err => {
      console.log('[Billboard Preview] Video autoplay notice:', err.message);
    });

    // When the episode preview video reaches near the end, pick another random episode to loop!
    billboardVideo.onended = () => {
      startRandomPreview();
    };
  }

  function checkResumeProgress() {
    if (!series || !series.episodes) return;

    // Find the latest watched episode
    let latestWatchedEp = null;
    let latestWatchedPos = 0;

    for (const ep of series.episodes) {
      const pos = parseFloat(localStorage.getItem(`cinedata_pos_${ep.id}`) || '0');
      if (pos > 15) {
        latestWatchedEp = ep;
        latestWatchedPos = pos;
        break;
      }
    }

    if (latestWatchedEp) {
      btnResumeSeries.style.display = 'inline-flex';
      const timeStr = window.playerInstance
        ? window.playerInstance.formatTime(latestWatchedPos)
        : 'saved spot';
      resumeEpText.textContent = `Resume S${latestWatchedEp.season || 1}:E${latestWatchedEp.episode || 1} (${timeStr})`;

      btnResumeSeries.onclick = () => {
        playEpisode(latestWatchedEp);
      };
    } else {
      btnResumeSeries.style.display = 'none';
    }
  }

  function renderEpisodes() {
    netflixEpisodesGrid.innerHTML = '';

    series.episodes.forEach((ep, index) => {
      const epCard = document.createElement('article');
      epCard.className = 'netflix-ep-card';
      epCard.setAttribute('role', 'button');
      epCard.setAttribute('tabindex', '0');
      epCard.setAttribute('aria-label', `Play Episode ${ep.episode}: ${ep.title}`);

      // Progress check from localStorage
      const savedPos = parseFloat(localStorage.getItem(`cinedata_pos_${ep.id}`) || '0');
      const savedDur = parseFloat(localStorage.getItem(`cinedata_dur_${ep.id}`) || '0');
      let progressPct = 0;
      if (savedDur > 0 && savedPos > 0) {
        progressPct = Math.min(100, (savedPos / savedDur) * 100);
      }

      const epNumStr = String(ep.episode || (index + 1));
      const seasonNumStr = `S${String(ep.season || 1).padStart(2, '0')}E${String(ep.episode || (index + 1)).padStart(2, '0')}`;

      epCard.innerHTML = `
        <div class="netflix-ep-thumb-wrap">
          <img class="netflix-ep-thumb" src="/api/thumbnail/${ep.id}" alt="${ep.fileName}" loading="lazy">
          <div class="ep-index-badge">${epNumStr}</div>
          <div class="ep-top-badges">
            <span class="badge-tag badge-dark">${seasonNumStr}</span>
            <div style="display: flex; gap: 4px;">
              ${ep.hasSubtitles ? '<span class="badge-tag badge-sub">SUB</span>' : ''}
              <span class="badge-tag badge-format">${ep.format}</span>
            </div>
          </div>
          <div class="play-hover-overlay">
            <div class="play-circle">
              <svg viewBox="0 0 24 24" fill="currentColor">
                <polygon points="6 4 19 12 6 20 6 4"></polygon>
              </svg>
            </div>
          </div>
          ${progressPct > 0 ? `
            <div class="card-progress-bar">
              <div class="card-progress-fill" style="width: ${progressPct}%"></div>
            </div>
          ` : ''}
        </div>
        <div class="netflix-ep-body">
          <div class="netflix-ep-title-row">
            <h3 class="netflix-ep-title">${ep.title || `Episode ${ep.episode}`}</h3>
            <span class="netflix-ep-size">${ep.sizeFormatted}</span>
          </div>
          <p class="netflix-ep-filename" title="${ep.fileName}">${ep.fileName}</p>
          <div class="netflix-ep-meta-row">
            <span class="netflix-ep-format">${ep.format} Direct Stream</span>
            <span class="netflix-ep-status">${progressPct > 5 ? `${Math.round(progressPct)}% watched` : 'Ready to watch'}</span>
          </div>
        </div>
      `;

      epCard.addEventListener('click', () => playEpisode(ep));
      epCard.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          playEpisode(ep);
        }
      });

      netflixEpisodesGrid.appendChild(epCard);
    });
  }

  function playEpisode(ep) {
    if (!window.playerInstance) return;

    // Pause the background billboard preview while watching
    billboardVideo.pause();

    window.playerInstance.play(ep, series.episodes);
  }

  function setupEventListeners() {
    // Floating header background blur on scroll
    window.addEventListener('scroll', () => {
      const nav = document.getElementById('navbar');
      if (nav) {
        if (window.scrollY > 30) {
          nav.classList.add('scrolled');
        } else {
          nav.classList.remove('scrolled');
        }
      }
    });

    // Primary Play Button: Play Episode 1
    btnPlayFirstEp.addEventListener('click', () => {
      if (series && series.episodes && series.episodes.length > 0) {
        playEpisode(series.episodes[0]);
      }
    });

    // Shuffle Preview Button: Switches to another random episode clip
    btnShufflePreview.addEventListener('click', () => {
      startRandomPreview();
      showToast('Switched to another random episode preview');
    });

    // Audio Mute/Unmute Toggle for Billboard Banner Video
    btnToggleAudio.addEventListener('click', () => {
      isAudioMuted = !isAudioMuted;
      billboardVideo.muted = isAudioMuted;

      if (isAudioMuted) {
        iconAudioMuted.style.display = 'block';
        iconAudioPlaying.style.display = 'none';
        audioText.textContent = 'Unmute Audio';
      } else {
        iconAudioMuted.style.display = 'none';
        iconAudioPlaying.style.display = 'block';
        audioText.textContent = 'Mute Audio';
        showToast('Preview sound enabled');
      }
    });

    // When Fullscreen Player closes, re-check progress and resume billboard preview
    window.addEventListener('cinedata-closed', () => {
      checkResumeProgress();
      renderEpisodes();
      billboardVideo.play().catch(() => {});
    });

    // Smart TV Remote D-Pad Navigation for Episodes
    document.addEventListener('keydown', (e) => {
      const playerOverlay = document.getElementById('playerOverlay');
      if (playerOverlay && playerOverlay.style.display !== 'none') return;
      if (connectModal && connectModal.open) return;

      if (e.key === 'Escape' || e.key === 'Back' || e.key === 'BrowserBack') {
        window.location.href = '/';
        return;
      }

      const cards = Array.from(netflixEpisodesGrid.querySelectorAll('.netflix-ep-card'));
      if (cards.length === 0) return;

      const activeEl = document.activeElement;
      const currentIndex = cards.indexOf(activeEl);

      if (['ArrowRight', 'ArrowLeft', 'ArrowDown', 'ArrowUp'].includes(e.key)) {
        if (currentIndex === -1) {
          if (e.key === 'ArrowDown') {
            cards[0].focus();
            e.preventDefault();
          }
          return;
        }

        const gridComputed = window.getComputedStyle(netflixEpisodesGrid);
        const colsCount = gridComputed.getPropertyValue('grid-template-columns').split(' ').length || 3;
        let targetIndex = currentIndex;

        if (e.key === 'ArrowRight') targetIndex = Math.min(cards.length - 1, currentIndex + 1);
        else if (e.key === 'ArrowLeft') targetIndex = Math.max(0, currentIndex - 1);
        else if (e.key === 'ArrowDown') targetIndex = Math.min(cards.length - 1, currentIndex + colsCount);
        else if (e.key === 'ArrowUp') {
          if (currentIndex - colsCount < 0) {
            btnPlayFirstEp.focus();
            e.preventDefault();
            return;
          }
          targetIndex = Math.max(0, currentIndex - colsCount);
        }

        if (cards[targetIndex]) {
          e.preventDefault();
          cards[targetIndex].focus();
          cards[targetIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
      }
    });

    // Connect Modal
    if (btnConnect) {
      btnConnect.addEventListener('click', () => {
        if (typeof connectModal.showModal === 'function') {
          connectModal.showModal();
        } else {
          connectModal.setAttribute('open', '');
        }
      });
    }

    closeConnectModal.addEventListener('click', () => {
      connectModal.close();
    });

    connectModal.addEventListener('click', (e) => {
      const rect = connectModal.getBoundingClientRect();
      const isInDialog = (
        rect.top <= e.clientY && e.clientY <= rect.top + rect.height &&
        rect.left <= e.clientX && e.clientX <= rect.left + rect.width
      );
      if (!isInDialog) {
        connectModal.close();
      }
    });

    // Copy URL button
    btnCopyUrl.addEventListener('click', () => {
      serverUrlInput.select();
      navigator.clipboard.writeText(serverUrlInput.value).then(() => {
        copyText.textContent = 'Copied!';
        showToast('Streaming URL copied to clipboard');
        setTimeout(() => { copyText.textContent = 'Copy'; }, 2000);
      });
    });
  }

  async function loadServerInfo() {
    try {
      const res = await fetch('/api/server-info');
      const data = await res.json();
      if (data.primaryUrl) serverUrlInput.value = data.primaryUrl;
      if (data.qrCodeDataUrl) modalQrImage.src = data.qrCodeDataUrl;
    } catch (e) {}
  }

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => {
      toast.classList.remove('show');
    }, 3000);
  }

  document.addEventListener('DOMContentLoaded', init);
})();
