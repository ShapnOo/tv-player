const express = require('express');
const cors = require('cors');
const path = require('path');
const os = require('os');
const fs = require('fs');
const QRCode = require('qrcode');

const { scanDirectory, formatBytes } = require('./scanner');
const { streamVideo, transmuxVideo, transcodeVideo } = require('./stream');
const { serveSubtitle, extractEmbeddedSubtitle } = require('./subtitles');
const { getThumbnail } = require('./thumbnails');

const app = express();
const PORT = process.env.PORT || 5050;
const MEDIA_DIR = path.join(__dirname, '..', 'Media');
const APPS_DIR = path.join(MEDIA_DIR, 'mobile app');
if (!fs.existsSync(APPS_DIR)) {
  try {
    fs.mkdirSync(APPS_DIR, { recursive: true });
  } catch (e) {}
}

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

// In-memory catalog
let catalog = { movies: [], series: [], allFlat: [] };
let mediaMap = new Map();
let seriesMapById = new Map();
const sseClients = new Set();

function notifyClients() {
  const payload = JSON.stringify({
    type: 'catalog_updated',
    count: catalog.allFlat.length,
    moviesCount: catalog.movies.length,
    seriesCount: catalog.series.length,
    timestamp: Date.now()
  });

  for (const client of sseClients) {
    try {
      client.write(`data: ${payload}\n\n`);
    } catch (e) {
      sseClients.delete(client);
    }
  }
}

// Auto-extract any ZIP archives dropped into Media
let isExtractingZip = false;
function checkAndExtractZips() {
  if (isExtractingZip) return;
  function walk(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.zip')) {
        isExtractingZip = true;
        console.log(`[Media Server] Auto-detecting and extracting zip archive: ${entry.name}...`);
        try {
          const targetDir = path.dirname(full);
          const { execSync } = require('child_process');
          execSync(`unzip -o -q "${full}" -d "${targetDir}"`, { timeout: 120000 });
          fs.unlinkSync(full);
          console.log(`[Media Server] Successfully unpacked ${entry.name}`);
        } catch (e) {
          console.error(`[Media Server] Error unpacking zip:`, e.message);
        } finally {
          isExtractingZip = false;
        }
      }
    }
  }
  try {
    walk(MEDIA_DIR);
  } catch (e) {}
}

function refreshCatalog() {
  try {
    checkAndExtractZips();
    const previousCount = catalog.allFlat.length;
    catalog = scanDirectory(MEDIA_DIR);

    mediaMap.clear();
    seriesMapById.clear();

    for (const m of catalog.movies) {
      mediaMap.set(m.id, m);
    }
    for (const s of catalog.series) {
      seriesMapById.set(s.id, s);
      for (const ep of s.episodes) {
        mediaMap.set(ep.id, ep);
      }
    }
    for (const it of catalog.allFlat) {
      mediaMap.set(it.id, it);
    }

    console.log(`[Media Server] Catalog refreshed. Discovered ${catalog.movies.length} movie(s) & ${catalog.series.length} series (${catalog.allFlat.length} total files).`);

    if (catalog.allFlat.length !== previousCount || previousCount === 0) {
      notifyClients();
    }
  } catch (err) {
    console.error('[Media Server] Error scanning media:', err.message);
  }
}

// Initial scan
refreshCatalog();

// Watch Media directory for live changes (Debounced FSEvents)
let watchDebounceTimer = null;
try {
  fs.watch(MEDIA_DIR, { recursive: true }, (eventType, filename) => {
    if (filename && (filename.startsWith('.') || filename.endsWith('.tmp') || filename.endsWith('.crdownload'))) return;
    clearTimeout(watchDebounceTimer);
    watchDebounceTimer = setTimeout(() => {
      console.log(`[Media Server] Detected file change in Media: ${filename || ''}. Updating catalog...`);
      refreshCatalog();
      notifyClients();
    }, 1000);
  });
} catch (err) {
  console.warn('[Media Server] Live file watcher notice:', err.message);
}

// Periodic background sync (4 seconds) - ensures external hard drives & USB sticks auto-sync instantly
setInterval(() => {
  try {
    const current = scanDirectory(MEDIA_DIR);
    if (current.allFlat.length !== catalog.allFlat.length) {
      console.log(`[Media Server] Auto-detected media file change. Syncing to all screens...`);
      refreshCatalog();
    }
  } catch (e) {}
}, 4000);

// Helper to get local network IP addresses
function getLocalIps() {
  const interfaces = os.networkInterfaces();
  const addresses = [];

  // Check en0 / en1 first (standard macOS Wi-Fi & Ethernet)
  const priorityNames = ['en0', 'en1', 'eth0', 'wlan0'];
  for (const name of priorityNames) {
    if (interfaces[name]) {
      for (const iface of interfaces[name]) {
        if (iface.family === 'IPv4' && !iface.internal) {
          addresses.push(iface.address);
        }
      }
    }
  }

  // Then add any other valid IPv4 non-tunnel interfaces
  for (const name of Object.keys(interfaces)) {
    if (priorityNames.includes(name) || name.startsWith('utun') || name.startsWith('lo')) continue;
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal && !addresses.includes(iface.address)) {
        addresses.push(iface.address);
      }
    }
  }

  // Fallback to any remaining non-internal IPv4
  if (addresses.length === 0) {
    for (const name of Object.keys(interfaces)) {
      for (const iface of interfaces[name]) {
        if (iface.family === 'IPv4' && !iface.internal && !addresses.includes(iface.address)) {
          addresses.push(iface.address);
        }
      }
    }
  }

  return addresses;
}

// API Routes
app.get('/api/server-info', async (req, res) => {
  const ips = getLocalIps();
  const primaryIp = ips[0] || 'localhost';
  const primaryUrl = `http://${primaryIp}:${PORT}`;

  let qrCodeDataUrl = '';
  try {
    qrCodeDataUrl = await QRCode.toDataURL(primaryUrl, {
      margin: 1,
      color: {
        dark: '#ffffff',
        light: '#0b0d13'
      },
      width: 256
    });
  } catch (e) {
    console.error('Failed to generate QR code:', e);
  }

  res.json({
    status: 'online',
    port: PORT,
    ips,
    primaryUrl,
    qrCodeDataUrl,
    mediaCount: catalog.allFlat.length,
    moviesCount: catalog.movies.length,
    seriesCount: catalog.series.length,
    mediaPath: MEDIA_DIR
  });
});

// Real-Time Server-Sent Events (SSE) for instant sync to TV & Mobile
app.get('/api/events', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*'
  });

  res.write(`data: ${JSON.stringify({ type: 'connected', count: catalog.allFlat.length })}\n\n`);
  sseClients.add(res);

  req.on('close', () => {
    sseClients.delete(res);
  });
});

app.get('/api/media', (req, res) => {
  const { type, query } = req.query;
  let movies = [...catalog.movies];
  let series = [...catalog.series];
  let all = [...catalog.allFlat];

  if (query) {
    const q = query.toLowerCase().trim();
    movies = movies.filter(m =>
      m.cleanTitle.toLowerCase().includes(q) ||
      m.fileName.toLowerCase().includes(q) ||
      (m.year && m.year.includes(q))
    );
    series = series.filter(s =>
      s.title.toLowerCase().includes(q) ||
      s.episodes.some(e => e.fileName.toLowerCase().includes(q) || e.title.toLowerCase().includes(q))
    );
    all = all.filter(it =>
      it.cleanTitle.toLowerCase().includes(q) ||
      it.fileName.toLowerCase().includes(q) ||
      (it.year && it.year.includes(q))
    );
  }

  res.json({
    total: all.length,
    moviesCount: movies.length,
    seriesCount: series.length,
    movies,
    series,
    items: all
  });
});

// Watch Progress & History persistence (Netflix-style cross-device tracking)
const PROGRESS_FILE = path.join(__dirname, '..', '.progress.json');
let watchProgress = {};
try {
  if (fs.existsSync(PROGRESS_FILE)) {
    watchProgress = JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8'));
  }
} catch (e) {
  watchProgress = {};
}

function saveWatchProgress() {
  try {
    fs.writeFileSync(PROGRESS_FILE, JSON.stringify(watchProgress, null, 2), 'utf8');
  } catch (e) {}
}

app.get('/api/progress', (req, res) => {
  res.json(watchProgress);
});

app.get('/api/progress/:id', (req, res) => {
  const p = watchProgress[req.params.id] || { pos: 0, dur: 0, watched: false, updatedAt: 0 };
  res.json(p);
});

app.post('/api/progress/:id', (req, res) => {
  const { id } = req.params;
  const { pos = 0, dur = 0, title = '', seriesTitle = '' } = req.body || {};
  const posSec = Math.round(Number(pos) || 0);
  const durSec = Math.round(Number(dur) || 0);

  if (posSec < 5 && !watchProgress[id]) {
    return res.json({ success: true, progress: null });
  }

  const isWatched = durSec > 0 ? (posSec / durSec >= 0.9) : false;
  watchProgress[id] = {
    id,
    pos: posSec,
    dur: durSec,
    watched: isWatched,
    title: title || (watchProgress[id]?.title || ''),
    seriesTitle: seriesTitle || (watchProgress[id]?.seriesTitle || ''),
    updatedAt: Date.now()
  };
  saveWatchProgress();
  res.json({ success: true, progress: watchProgress[id] });
});

app.get('/series/:id', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'series.html'));
});

// App Store / Download APK routes
app.get('/apps', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'apps.html'));
});

app.get('/api/apps', (req, res) => {
  try {
    if (!fs.existsSync(APPS_DIR)) {
      return res.json({ count: 0, apps: [] });
    }
    const files = fs.readdirSync(APPS_DIR);
    const apkFiles = files.filter(f => f.toLowerCase().endsWith('.apk') && !f.startsWith('.'));
    const apps = apkFiles.map(file => {
      const fullPath = path.join(APPS_DIR, file);
      const stats = fs.statSync(fullPath);
      const cleanName = file.replace(/\.apk$/i, '').replace(/[-_]/g, ' ');
      return {
        fileName: file,
        name: cleanName,
        sizeBytes: stats.size,
        sizeFormatted: formatBytes(stats.size),
        modifiedAt: stats.mtime.toISOString(),
        downloadUrl: `/api/apps/download/${encodeURIComponent(file)}`
      };
    });
    apps.sort((a, b) => new Date(b.modifiedAt) - new Date(a.modifiedAt));
    res.json({ count: apps.length, apps });
  } catch (err) {
    console.error('Error scanning mobile app directory:', err);
    res.status(500).json({ error: 'Failed to read apps directory', apps: [] });
  }
});

app.get('/api/apps/download/:fileName', (req, res) => {
  const fileName = req.params.fileName;
  const filePath = path.join(APPS_DIR, fileName);

  if (!filePath.startsWith(APPS_DIR) || !fs.existsSync(filePath)) {
    return res.status(404).send('APK file not found');
  }

  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
  res.download(filePath, fileName);
});

// Helper to find the latest APK in Media/mobile app/
function getLatestApk() {
  if (!fs.existsSync(APPS_DIR)) return null;
  const files = fs.readdirSync(APPS_DIR)
    .filter(f => f.toLowerCase().endsWith('.apk') && !f.startsWith('.'))
    .map(f => {
      const fullPath = path.join(APPS_DIR, f);
      const stat = fs.statSync(fullPath);
      return { file: f, fullPath, mtime: stat.mtime };
    })
    .sort((a, b) => b.mtime - a.mtime);
  return files.length > 0 ? files[0] : null;
}

// Ultra-short URL for typing easily on TV remotes or in "Downloader" app: http://<ip>:5050/d
app.get('/d', (req, res) => {
  const latest = getLatestApk();
  if (latest && fs.existsSync(latest.fullPath)) {
    res.setHeader('Content-Type', 'application/vnd.android.package-archive');
    res.setHeader('Content-Disposition', `attachment; filename="${latest.file}"`);
    return res.download(latest.fullPath, latest.file);
  }
  res.status(404).send('No APK found in Media/mobile app/');
});

// 1-Click Wireless ADB Installer from Laptop to Hisense TV
app.post('/api/install-tv', (req, res) => {
  const { tvIp } = req.body;
  if (!tvIp || typeof tvIp !== 'string') {
    return res.status(400).json({ success: false, error: 'Please provide a valid TV IP address (e.g. 10.81.100.45).' });
  }

  const cleanIp = tvIp.trim();
  const adbPath = '/Users/shapno/Library/Android/sdk/platform-tools/adb';
  const latest = getLatestApk();

  if (!latest || !fs.existsSync(latest.fullPath)) {
    return res.status(404).json({ success: false, error: 'No APK found in Media/mobile app/' });
  }

  const apkPath = latest.fullPath;


  console.log(`[TV Installer] Connecting to TV at ${cleanIp}:5555...`);

  const { exec } = require('child_process');
  exec(`"${adbPath}" connect ${cleanIp}:5555`, { timeout: 8000 }, (connErr, connStdout) => {
    console.log(`[TV Installer] ADB connect output:`, connStdout);

    exec(`"${adbPath}" -s ${cleanIp}:5555 install -r "${apkPath}"`, { timeout: 60000 }, (instErr, instStdout, instStderr) => {
      if (instErr) {
        console.error(`[TV Installer] Install error:`, instStderr || instErr.message);
        return res.status(500).json({
          success: false,
          error: `Could not connect or install to ${cleanIp}. Make sure Wireless Debugging / Developer Mode is turned ON in your Hisense TV Settings.`
        });
      }

      console.log(`[TV Installer] Install success:`, instStdout);
      return res.json({
        success: true,
        message: `Successfully installed Shapno TV on your Hisense TV (${cleanIp})! Look for 'Shapno TV' in your Google TV apps row.`
      });
    });
  });
});

app.get('/api/series/:id', (req, res) => {
  const s = seriesMapById.get(req.params.id);
  if (!s) {
    return res.status(404).json({ error: 'Series not found' });
  }
  res.json(s);
});

app.get('/api/media/:id', (req, res) => {
  const item = mediaMap.get(req.params.id);
  if (!item) {
    return res.status(404).json({ error: 'Media not found' });
  }
  res.json(item);
});

app.get('/api/stream/:id', (req, res) => {
  const item = mediaMap.get(req.params.id);
  if (!item) {
    return res.status(404).send('Media item not found');
  }

  // If client requests compatibility mode (for Dolby Vision / non-DV hardware)
  if (req.query.compat === '1' || req.query.mode === 'transmux' || (req.query.auto === '1' && item.isDolbyVision)) {
    return transmuxVideo(item.fullPath, req, res);
  }

  if (req.query.mode === 'transcode') {
    return transcodeVideo(item.fullPath, req, res);
  }

  streamVideo(item.fullPath, req, res);
});

// Real-time lossless MP4 transmuxer for Smart TVs and Apple devices
app.get('/api/transmux/:id', (req, res) => {
  const item = mediaMap.get(req.params.id);
  if (!item) {
    return res.status(404).send('Media item not found');
  }
  transmuxVideo(item.fullPath, req, res);
});

// Universal hardware transcode (1080p H.264) for devices without 4K/HEVC decoders
app.get('/api/transcode/:id', (req, res) => {
  const item = mediaMap.get(req.params.id);
  if (!item) {
    return res.status(404).send('Media item not found');
  }
  transcodeVideo(item.fullPath, req, res);
});

app.get('/api/thumbnail/:id', (req, res) => {
  const item = mediaMap.get(req.params.id);
  if (!item) {
    return res.status(404).send('Media item not found');
  }
  getThumbnail(item.id, item.fullPath, item.title, item.format, res);
});

app.get('/api/subtitles/:id', (req, res) => {
  const item = mediaMap.get(req.params.id);
  if (!item || !item.subtitles || item.subtitles.length === 0) {
    return res.status(404).send('Subtitle not found');
  }

  const subIndex = parseInt(req.query.index || '0', 10);
  const subFile = item.subtitles[subIndex] || item.subtitles[0];

  // If subtitle track is embedded in MKV/MP4, extract on-the-fly
  if (subFile.isEmbedded) {
    return extractEmbeddedSubtitle(item.id, item.fullPath, subFile.trackIndex || 0, res);
  }

  // Look up full path
  const subtitlePath = path.join(path.dirname(item.fullPath), subFile.name || subFile.label);
  if (fs.existsSync(subtitlePath)) {
    return serveSubtitle(subtitlePath, req, res);
  }

  // Fallback search
  const dir = path.dirname(item.fullPath);
  const found = fs.readdirSync(dir).find(f => f.endsWith('.srt') || f.endsWith('.vtt'));
  if (found) {
    return serveSubtitle(path.join(dir, found), req, res);
  }

  res.status(404).send('Subtitle file not found on disk');
});

app.post('/api/scan', (req, res) => {
  refreshCatalog();
  res.json({ success: true, count: catalog.allFlat.length, moviesCount: catalog.movies.length, seriesCount: catalog.series.length });
});

// Single Page Application fallback
app.use((req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

// Start Server
app.listen(PORT, '0.0.0.0', async () => {
  const ips = getLocalIps();
  console.log('\n=============================================================');
  console.log('   🍿 SHAPNO — MAC LOCAL MEDIA STREAMING SERVER IS LIVE!');
  console.log('=============================================================');
  console.log(`\n• Local (on this Mac):     http://localhost:${PORT}`);

  ips.forEach((ip, idx) => {
    console.log(`• Network (TV/Phone/LAN):  http://${ip}:${PORT}`);
  });

  console.log(`\n• Media Folder:            ${MEDIA_DIR}`);
  console.log(`• Total Catalog:           ${catalog.movies.length} Movies, ${catalog.series.length} Series (${catalog.allFlat.length} total files)`);
  console.log('=============================================================\n');

  if (ips.length > 0) {
    try {
      console.log('📱 Scan this QR code with your phone camera to stream:');
      const terminalQr = await QRCode.toString(`http://${ips[0]}:${PORT}`, { type: 'terminal', small: true });
      console.log(terminalQr);
    } catch (e) {
      // ignore
    }
  }
});
