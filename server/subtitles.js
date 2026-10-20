const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const CACHE_DIR = path.join(__dirname, '..', '.thumbnails');
if (!fs.existsSync(CACHE_DIR)) {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function getFfmpegPath() {
  if (fs.existsSync('/opt/homebrew/bin/ffmpeg')) {
    return '/opt/homebrew/bin/ffmpeg';
  }
  return 'ffmpeg';
}

function srtToVtt(srtContent) {
  let vtt = srtContent.replace(/\r\n|\r/g, '\n');
  vtt = vtt.replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
  return `WEBVTT\n\n${vtt.trim()}\n`;
}

function serveSubtitle(subtitlePath, req, res) {
  if (!fs.existsSync(subtitlePath)) {
    return res.status(404).send('Subtitle not found');
  }

  const ext = path.extname(subtitlePath).toLowerCase();
  const raw = fs.readFileSync(subtitlePath, 'utf8');

  res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
  res.setHeader('Access-Control-Allow-Origin', '*');

  if (ext === '.vtt') {
    return res.send(raw);
  }

  const converted = srtToVtt(raw);
  res.send(converted);
}

/**
 * Extract embedded subtitle from MKV/MP4 using ffmpeg
 */
function extractEmbeddedSubtitle(mediaId, videoPath, subTrackIndex, res) {
  const cachedVtt = path.join(CACHE_DIR, `${mediaId}_sub_${subTrackIndex}.vtt`);

  if (fs.existsSync(cachedVtt)) {
    res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    return fs.createReadStream(cachedVtt).pipe(res);
  }

  const ffmpeg = getFfmpegPath();
  const args = [
    '-i', videoPath,
    '-map', `0:s:${subTrackIndex}`,
    '-f', 'webvtt',
    '-y',
    cachedVtt
  ];

  const proc = spawn(ffmpeg, args);

  proc.on('close', (code) => {
    if (code === 0 && fs.existsSync(cachedVtt)) {
      res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Cache-Control', 'public, max-age=86400');
      fs.createReadStream(cachedVtt).pipe(res);
    } else {
      res.status(404).send('Embedded subtitle extraction failed');
    }
  });

  proc.on('error', () => {
    res.status(500).send('FFmpeg subtitle extraction error');
  });
}

module.exports = {
  serveSubtitle,
  extractEmbeddedSubtitle,
  srtToVtt
};
