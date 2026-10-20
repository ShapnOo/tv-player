const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const THUMBNAILS_DIR = path.join(__dirname, '..', '.thumbnails');
if (!fs.existsSync(THUMBNAILS_DIR)) {
  fs.mkdirSync(THUMBNAILS_DIR, { recursive: true });
}

// Find ffmpeg binary
function getFfmpegPath() {
  if (fs.existsSync('/opt/homebrew/bin/ffmpeg')) {
    return '/opt/homebrew/bin/ffmpeg';
  }
  return 'ffmpeg';
}

function generateSvgPoster(title, format) {
  const safeTitle = (title || 'Media File').replace(/[<>&]/g, '');
  return `<svg width="480" height="270" viewBox="0 0 480 270" fill="none" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#141724" />
        <stop offset="50%" stop-color="#1f2338" />
        <stop offset="100%" stop-color="#0b0d13" />
      </linearGradient>
      <linearGradient id="glow" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#6366f1" />
        <stop offset="100%" stop-color="#ec4899" />
      </linearGradient>
    </defs>
    <rect width="480" height="270" fill="url(#grad)" rx="12" />
    <circle cx="240" cy="115" r="38" fill="url(#glow)" fill-opacity="0.2" />
    <circle cx="240" cy="115" r="30" stroke="url(#glow)" stroke-width="2" />
    <polygon points="234,103 252,115 234,127" fill="#ffffff" />
    <text x="240" y="185" text-anchor="middle" fill="#ffffff" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-weight="600" font-size="16">${safeTitle.slice(0, 32)}</text>
    <rect x="215" y="205" width="50" height="20" rx="4" fill="rgba(255,255,255,0.12)" />
    <text x="240" y="219" text-anchor="middle" fill="#94a3b8" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="11" font-weight="700">${format || 'HD'}</text>
  </svg>`;
}

function getThumbnail(id, videoPath, title, format, res) {
  const thumbPath = path.join(THUMBNAILS_DIR, `${id}.jpg`);

  if (fs.existsSync(thumbPath)) {
    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    return fs.createReadStream(thumbPath).pipe(res);
  }

  // Determine seek timestamp: larger movies/episodes seek into 2 min to avoid black intro screens
  let seekTime = '00:00:03';
  try {
    const stats = fs.statSync(videoPath);
    if (stats.size > 50 * 1024 * 1024) {
      seekTime = '00:02:15';
    }
  } catch (e) {}

  // Generate thumbnail using ffmpeg
  const ffmpeg = getFfmpegPath();
  const args = [
    '-ss', seekTime,
    '-i', videoPath,
    '-vframes', '1',
    '-vf', 'scale=640:-1',
    '-q:v', '2',
    '-y',
    thumbPath
  ];

  const proc = spawn(ffmpeg, args);

  proc.on('close', (code) => {
    if (code === 0 && fs.existsSync(thumbPath)) {
      res.setHeader('Content-Type', 'image/jpeg');
      res.setHeader('Cache-Control', 'public, max-age=86400');
      fs.createReadStream(thumbPath).pipe(res);
    } else {
      // Fallback SVG poster
      res.setHeader('Content-Type', 'image/svg+xml');
      res.setHeader('Cache-Control', 'public, max-age=3600');
      res.send(generateSvgPoster(title, format));
    }
  });

  proc.on('error', () => {
    res.setHeader('Content-Type', 'image/svg+xml');
    res.send(generateSvgPoster(title, format));
  });
}

module.exports = {
  getThumbnail,
  generateSvgPoster
};
