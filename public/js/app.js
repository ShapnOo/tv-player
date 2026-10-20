/**
 * Shapno Main Frontend Application
 * Media Catalog, Categorized Sections (Movies & Series), Folder-Based Series Explorer,
 * Random Thumbnails, Real-time Sync & Smart TV D-Pad Remote Support.
 */

(function () {
  let moviesList = [];
  let seriesList = [];
  let allFlatList = [];
  let currentFilter = 'all'; // 'all' | 'movie' | 'series'
  let serverInfo = null;
  let activeSeriesForModal = null;

  // DOM Elements - Sections & Grids
  const moviesSection = document.getElementById('moviesSection');
  const seriesSection = document.getElementById('seriesSection');
  const moviesGrid = document.getElementById('moviesGrid');
  const seriesGrid = document.getElementById('seriesGrid');
  const moviesCountBadge = document.getElementById('moviesCountBadge');
  const seriesCountBadge = document.getElementById('seriesCountBadge');
  const emptyState = document.getElementById('emptyState');

  // Navigation & Search
  const categoryTabs = document.getElementById('categoryTabs');
  const searchInput = document.getElementById('searchInput');
  const btnRescan = document.getElementById('btnRescan');
  const btnEmptyRescan = document.getElementById('btnEmptyRescan');

  // Connect Devices Modal
  const btnConnect = document.getElementById('btnConnect');
  const connectModal = document.getElementById('connectModal');
  const closeConnectModal = document.getElementById('closeConnectModal');
  const modalQrImage = document.getElementById('modalQrImage');
  const serverUrlInput = document.getElementById('serverUrlInput');
  const btnCopyUrl = document.getElementById('btnCopyUrl');
  const copyText = document.getElementById('copyText');
  const toast = document.getElementById('toast');

  // Hero Spotlight elements
  const heroSpotlight = document.getElementById('heroSpotlight');
  const heroBackdrop = document.getElementById('heroBackdrop');
  const heroTitle = document.getElementById('heroTitle');
  const heroMeta = document.getElementById('heroMeta');
  const heroType = document.getElementById('heroType');
  const heroFormat = document.getElementById('heroFormat');
  const heroSize = document.getElementById('heroSize');
  const heroPlayBtn = document.getElementById('heroPlayBtn');
  const heroResumeBtn = document.getElementById('heroResumeBtn');
  const heroResumeTime = document.getElementById('heroResumeTime');

  let featuredMedia = null;

  // Initialize Application
  async function init() {
    setupEventListeners();
    await loadServerInfo();
    await fetchMedia();
    initRealtimeSync();
  }

  // Real-time Live Sync across TV, Phone, and Mac (Server-Sent Events)
  function initRealtimeSync() {
    if (typeof window.EventSource === 'undefined') {
      setInterval(fetchMedia, 6000);
      return;
    }

    function connectSSE() {
      const eventSource = new EventSource('/api/events');

      eventSource.onmessage = (e) => {
        try {
          const data = JSON.parse(e.data);
          if (data.type === 'catalog_updated') {
            const oldCount = allFlatList.length;
            fetchMedia().then(() => {
              if (data.count > oldCount) {
                showToast('🎬 Library updated: New media ready to stream');
              }
            });
          }
        } catch (err) {}
      };

      eventSource.onerror = () => {
        eventSource.close();
        setTimeout(connectSSE, 4000);
      };
    }

    connectSSE();

    // Re-check immediately if TV or mobile device wakes from sleep
    window.addEventListener('focus', () => fetchMedia());
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) fetchMedia();
    });
  }

  function setupEventListeners() {
    // Category Tabs filter switching
    categoryTabs.addEventListener('click', (e) => {
      const btn = e.target.closest('.tab-btn');
      if (!btn) return;
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.dataset.type; // 'all' | 'movie' | 'series'
      renderCatalogs();
    });

    // Search Input
    searchInput.addEventListener('input', () => {
      renderCatalogs();
    });

    // Keyboard shortcut '/' to instantly focus search
    document.addEventListener('keydown', (e) => {
      if (e.key === '/' && document.activeElement !== searchInput) {
        const playerOverlay = document.getElementById('playerOverlay');
        if (playerOverlay && playerOverlay.style.display !== 'none') return;
        e.preventDefault();
        searchInput.focus();
      }
    });

    // TV Remote D-Pad Grid Navigation (Smart TV / Set-top box keyboard controls)
    document.addEventListener('keydown', (e) => {
      const playerOverlay = document.getElementById('playerOverlay');
      if (playerOverlay && playerOverlay.style.display !== 'none') return;
      if (connectModal && connectModal.open) return;
      if (document.activeElement === searchInput) return;

      // In main view: collect all currently visible cards
      const visibleCards = Array.from(document.querySelectorAll('.catalog-section:not([style*="display: none"]) .media-card'));
      if (visibleCards.length === 0) return;

      const activeEl = document.activeElement;
      const currentIndex = visibleCards.indexOf(activeEl);

      if (['ArrowRight', 'ArrowLeft', 'ArrowDown', 'ArrowUp'].includes(e.key)) {
        if (currentIndex === -1) {
          if (e.key === 'ArrowDown') {
            visibleCards[0].focus();
            e.preventDefault();
          }
          return;
        }

        // Estimate columns based on container width
        const gridEl = activeEl.closest('.media-grid');
        const gridComputed = gridEl ? window.getComputedStyle(gridEl) : null;
        const colsCount = gridComputed ? (gridComputed.getPropertyValue('grid-template-columns').split(' ').length || 3) : 3;

        let targetIndex = currentIndex;
        if (e.key === 'ArrowRight') {
          targetIndex = Math.min(visibleCards.length - 1, currentIndex + 1);
        } else if (e.key === 'ArrowLeft') {
          targetIndex = Math.max(0, currentIndex - 1);
        } else if (e.key === 'ArrowDown') {
          targetIndex = Math.min(visibleCards.length - 1, currentIndex + colsCount);
        } else if (e.key === 'ArrowUp') {
          if (currentIndex - colsCount < 0) {
            if (heroPlayBtn && heroSpotlight.style.display !== 'none') {
              heroPlayBtn.focus();
            } else {
              document.querySelector('.tab-btn.active')?.focus();
            }
            e.preventDefault();
            return;
          }
          targetIndex = Math.max(0, currentIndex - colsCount);
        }

        if (visibleCards[targetIndex]) {
          e.preventDefault();
          visibleCards[targetIndex].focus();
          visibleCards[targetIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
      }
    });

    // Helper for D-pad navigation inside grids
    function handleGridDpad(container, e) {
      const cards = Array.from(container.querySelectorAll('.episode-card'));
      if (cards.length === 0) return;
      const activeEl = document.activeElement;
      const currentIndex = cards.indexOf(activeEl);

      if (['ArrowRight', 'ArrowLeft', 'ArrowDown', 'ArrowUp'].includes(e.key)) {
        if (currentIndex === -1) {
          cards[0].focus();
          e.preventDefault();
          return;
        }

        const gridComputed = window.getComputedStyle(container);
        const colsCount = gridComputed.getPropertyValue('grid-template-columns').split(' ').length || 3;
        let targetIndex = currentIndex;

        if (e.key === 'ArrowRight') targetIndex = Math.min(cards.length - 1, currentIndex + 1);
        else if (e.key === 'ArrowLeft') targetIndex = Math.max(0, currentIndex - 1);
        else if (e.key === 'ArrowDown') targetIndex = Math.min(cards.length - 1, currentIndex + colsCount);
        else if (e.key === 'ArrowUp') targetIndex = Math.max(0, currentIndex - colsCount);

        if (cards[targetIndex]) {
          e.preventDefault();
          cards[targetIndex].focus();
          cards[targetIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
      }
    }

    // Rescan buttons
    btnRescan.addEventListener('click', () => triggerRescan());
    btnEmptyRescan.addEventListener('click', () => triggerRescan());

    // Connect Devices Modal
    btnConnect.addEventListener('click', () => {
      if (typeof connectModal.showModal === 'function') {
        connectModal.showModal();
      } else {
        connectModal.setAttribute('open', '');
      }
    });

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

    // Hero Play and Resume buttons
    heroPlayBtn.addEventListener('click', () => {
      if (featuredMedia && window.playerInstance) {
        if (featuredMedia.type === 'series') {
          window.location.href = `/series.html?id=${featuredMedia.id}`;
        } else {
          window.playerInstance.play(featuredMedia, moviesList);
        }
      }
    });

    heroResumeBtn.addEventListener('click', () => {
      if (featuredMedia && window.playerInstance) {
        const itemToPlay = (featuredMedia.type === 'series' && featuredMedia.episodes)
          ? featuredMedia.episodes[0]
          : featuredMedia;
        window.playerInstance.play(itemToPlay, [itemToPlay]);
      }
    });

    // Refresh progress indicators when video player closes
    window.addEventListener('cinedata-closed', () => {
      renderCatalogs();
      updateHeroResume();
    });
  }

  async function loadServerInfo() {
    try {
      const res = await fetch('/api/server-info');
      serverInfo = await res.json();

      if (serverInfo.primaryUrl) {
        serverUrlInput.value = serverInfo.primaryUrl;
      }
      if (serverInfo.qrCodeDataUrl) {
        modalQrImage.src = serverInfo.qrCodeDataUrl;
      }
    } catch (err) {
      console.error('Failed to load server info:', err);
    }
  }

  async function fetchMedia() {
    try {
      const res = await fetch('/api/media');
      const data = await res.json();
      moviesList = data.movies || [];
      seriesList = data.series || [];
      allFlatList = data.items || [];

      renderFeaturedSpotlight();
      renderCatalogs();
    } catch (err) {
      console.error('Failed to load media catalog:', err);
      showToast('Error loading media files');
    }
  }

  async function triggerRescan() {
    btnRescan.classList.add('spinning');
    try {
      const res = await fetch('/api/scan', { method: 'POST' });
      const data = await res.json();
      await fetchMedia();
      showToast(`Scan complete: ${data.count} items in library`);
    } catch (err) {
      showToast('Scan failed');
    } finally {
      setTimeout(() => {
        btnRescan.classList.remove('spinning');
      }, 600);
    }
  }

  // Render the Hero Spotlight Banner with the first movie or series
  function renderFeaturedSpotlight() {
    if (moviesList.length === 0 && seriesList.length === 0) {
      heroSpotlight.style.display = 'none';
      return;
    }

    // Pick top movie or top series
    featuredMedia = moviesList.length > 0 ? moviesList[0] : seriesList[0];
    heroSpotlight.style.display = 'flex';
    heroTitle.textContent = featuredMedia.title;

    if (featuredMedia.type === 'series') {
      heroType.textContent = 'TV Series';
      heroFormat.textContent = featuredMedia.format || 'HD';
      heroSize.textContent = featuredMedia.totalSizeFormatted || `${featuredMedia.episodesCount} Episodes`;
      heroMeta.textContent = `${featuredMedia.episodesCount} Episodes • Direct Mac Stream`;
      const thumbId = featuredMedia.randomEpisodeId || (featuredMedia.episodes[0] && featuredMedia.episodes[0].id);
      heroBackdrop.style.backgroundImage = `url('/api/thumbnail/${thumbId}')`;
    } else {
      heroType.textContent = 'Movie';
      heroFormat.textContent = featuredMedia.format;
      heroSize.textContent = featuredMedia.sizeFormatted;
      heroMeta.textContent = `${featuredMedia.year ? featuredMedia.year + ' • ' : ''}${featuredMedia.hasSubtitles ? 'Subtitles Ready • ' : ''}Direct Mac Stream`;
      heroBackdrop.style.backgroundImage = `url('/api/thumbnail/${featuredMedia.id}')`;
    }

    updateHeroResume();
  }

  function updateHeroResume() {
    if (!featuredMedia) return;
    const targetId = (featuredMedia.type === 'series' && featuredMedia.episodes && featuredMedia.episodes[0])
      ? featuredMedia.episodes[0].id
      : featuredMedia.id;

    const savedPos = localStorage.getItem(`cinedata_pos_${targetId}`);
    if (savedPos && parseFloat(savedPos) > 10) {
      heroResumeBtn.style.display = 'inline-flex';
      heroResumeTime.textContent = window.playerInstance ? window.playerInstance.formatTime(parseFloat(savedPos)) : 'saved spot';
    } else {
      heroResumeBtn.style.display = 'none';
    }
  }

  /**
   * Main Catalog Render:
   * Displays distinct Movies and Series sections according to active tab & search query.
   */
  function renderCatalogs() {
    const query = searchInput.value.toLowerCase().trim();

    // 1. Filter Movies
    const filteredMovies = moviesList.filter(item => {
      if (currentFilter === 'series') return false;
      if (!query) return true;
      return (
        item.cleanTitle.toLowerCase().includes(query) ||
        item.fileName.toLowerCase().includes(query) ||
        (item.year && item.year.includes(query)) ||
        item.format.toLowerCase().includes(query)
      );
    });

    // 2. Filter Series
    const filteredSeries = seriesList.filter(s => {
      if (currentFilter === 'movie') return false;
      if (!query) return true;
      const matchesTitle = s.title.toLowerCase().includes(query) || s.folderName.toLowerCase().includes(query);
      const matchesEp = s.episodes && s.episodes.some(ep =>
        ep.fileName.toLowerCase().includes(query) ||
        ep.title.toLowerCase().includes(query) ||
        (ep.cleanTitle && ep.cleanTitle.toLowerCase().includes(query))
      );
      return matchesTitle || matchesEp;
    });

    // Update section badges
    moviesCountBadge.textContent = `${filteredMovies.length} title${filteredMovies.length === 1 ? '' : 's'}`;
    seriesCountBadge.textContent = `${filteredSeries.length} series`;

    // Determine visibility of sections
    const showMovies = (currentFilter === 'all' || currentFilter === 'movie') && filteredMovies.length > 0;
    const showSeries = (currentFilter === 'all' || currentFilter === 'series') && filteredSeries.length > 0;

    if (!showMovies && !showSeries) {
      moviesSection.style.display = 'none';
      seriesSection.style.display = 'none';
      emptyState.style.display = 'block';
      return;
    }

    emptyState.style.display = 'none';

    // Render Movies Section
    if (showMovies) {
      moviesSection.style.display = 'block';
      moviesGrid.innerHTML = '';
      filteredMovies.forEach(movie => {
        const card = createMovieCard(movie, filteredMovies);
        moviesGrid.appendChild(card);
      });
    } else {
      moviesSection.style.display = 'none';
    }

    // Render TV Series Section
    if (showSeries) {
      seriesSection.style.display = 'block';
      seriesGrid.innerHTML = '';
      filteredSeries.forEach(series => {
        const card = createSeriesCard(series);
        seriesGrid.appendChild(card);
      });
    } else {
      seriesSection.style.display = 'none';
    }
  }

  /**
   * Create a Movie Card
   */
  function createMovieCard(item, playlist) {
    const card = document.createElement('article');
    card.className = 'media-card';
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.setAttribute('aria-label', `Play Movie ${item.cleanTitle || item.title}`);

    // Saved playback progress
    const savedPos = parseFloat(localStorage.getItem(`cinedata_pos_${item.id}`) || '0');
    const savedDur = parseFloat(localStorage.getItem(`cinedata_dur_${item.id}`) || '0');
    let progressPct = 0;
    if (savedDur > 0 && savedPos > 0) {
      progressPct = Math.min(100, (savedPos / savedDur) * 100);
    }

    const subBadgeHtml = item.hasSubtitles
      ? `<span class="badge-tag badge-sub">SUB</span>`
      : '';

    card.innerHTML = `
      <div class="card-thumbnail-wrap">
        <img class="card-thumbnail" src="/api/thumbnail/${item.id}" alt="${item.cleanTitle || item.title}" loading="lazy">
        <div class="card-badges-top">
          <span class="badge-tag badge-type movie">MOVIE</span>
          <div style="display: flex; gap: 4px;">
            ${subBadgeHtml}
            <span class="badge-tag badge-format">${item.format}</span>
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
      <div class="card-body">
        <h3 class="card-title" title="${item.cleanTitle || item.title}">${item.cleanTitle || item.title}</h3>
        <p class="card-subtitle">
          ${item.year ? `<span>${item.year}</span> • ` : ''}
          <span>Movie</span>
        </p>
        <div class="card-meta-row">
          <span class="card-size">${item.sizeFormatted}</span>
          <span>${progressPct > 5 ? `${Math.round(progressPct)}% watched` : 'Ready to stream'}</span>
        </div>
      </div>
    `;

    const playAction = () => {
      if (window.playerInstance) {
        window.playerInstance.play(item, playlist);
      }
    };

    card.addEventListener('click', playAction);
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        playAction();
      }
    });

    return card;
  }

  /**
   * Create a Series Card:
   * - Folder name is strictly the series name!
   * - Displays a dynamically chosen random episode thumbnail!
   * - Clicking opens the Series Episodes Explorer Modal.
   */
  function createSeriesCard(series) {
    const card = document.createElement('article');
    card.className = 'media-card series-card';
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.setAttribute('aria-label', `Explore TV Series ${series.title}`);

    // Dynamic random thumbnail: use the server-provided random thumbnail ID or select one
    let thumbnailEpisodeId = series.randomEpisodeId;
    if (!thumbnailEpisodeId && series.episodes && series.episodes.length > 0) {
      const randIdx = Math.floor(Math.random() * series.episodes.length);
      thumbnailEpisodeId = series.episodes[randIdx].id;
    }

    card.innerHTML = `
      <div class="card-thumbnail-wrap">
        <img class="card-thumbnail" src="/api/thumbnail/${thumbnailEpisodeId}" alt="${series.title}" loading="lazy">
        <div class="card-badges-top">
          <span class="badge-tag badge-type series">TV SERIES</span>
          <div class="series-badge-row">
            <span class="series-episodes-pill">${series.episodesCount} Episodes</span>
            <span class="badge-tag badge-format">${series.format || 'HD'}</span>
          </div>
        </div>
        <div class="play-hover-overlay">
          <div class="play-circle">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <rect x="2" y="7" width="20" height="15" rx="2" ry="2"></rect>
              <polyline points="17 2 12 7 7 2"></polyline>
            </svg>
          </div>
        </div>
      </div>
      <div class="card-body">
        <h3 class="card-title" title="${series.title}">${series.title}</h3>
        <p class="card-subtitle">
          <span>Folder: <strong>${series.folderName}</strong></span>
        </p>
        <div class="card-meta-row">
          <span class="card-size">${series.totalSizeFormatted}</span>
          <span>Click to view episodes</span>
        </div>
      </div>
    `;

    const openAction = () => {
      window.location.href = `/series.html?id=${series.id}`;
    };

    card.addEventListener('click', openAction);
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        openAction();
      }
    });

    return card;
  }

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => {
      toast.classList.remove('show');
    }, 3000);
  }

  // Run on DOM load
  document.addEventListener('DOMContentLoaded', init);
})();
