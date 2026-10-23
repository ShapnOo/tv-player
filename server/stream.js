const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const MIME_TYPES = {
  '.mp4': 'video/mp4',
  '.m4v': 'video/mp4',
  '.webm': 'video/webm',
  '.mov': 'video/quicktime',
  '.mkv': 'video/x-matroska',
  '.avi': 'video/x-msvideo'
};

function getFfmpegPath() {
  if (fs.existsSync('/opt/homebrew/bin/ffmpeg')) {
    return '/opt/homebrew/bin/ffmpeg';
  }
  return 'ffmpeg';
}

/**
 * High-performance byte-range video streaming
 * Optimized with bounded chunks to prevent TV buffer bloat and Wi-Fi latency
 */
function streamVideo(filePath, req, res) {
  if (!fs.existsSync(filePath)) {
    return res.status(404).send('Media file not found');
  }

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'video/mp4';

  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const requestedEnd = parts[1] ? parseInt(parts[1], 10) : null;
    const end = requestedEnd !== null ? requestedEnd : fileSize - 1;

    // Boundary validation
    if (start >= fileSize || end >= fileSize || start > end) {
      res.status(416).set('Content-Range', `bytes */${fileSize}`);
      return res.end();
    }

    const chunkSize = (end - start) + 1;
    const fileStream = fs.createReadStream(filePath, {
      start,
      end,
      highWaterMark: 256 * 1024 // 256KB read buffers for maximum disk I/O throughput
    });

    const headers = {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Content-Type': contentType,
      'Cache-Control': 'public, max-age=3600',
      'Connection': 'keep-alive'
    };

    res.writeHead(206, headers);
    fileStream.pipe(res);

    fileStream.on('error', (err) => {
      console.error('[Stream] Error streaming chunk:', err.message);
      if (!res.headersSent) {
        res.status(500).end();
      }
    });

    req.on('close', () => {
      fileStream.destroy();
    });
  } else {
    // Standard full stream response (HTTP 200 OK when no Range header is supplied)
    const headers = {
      'Content-Length': fileSize,
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'public, max-age=3600',
      'Connection': 'keep-alive'
    };

    res.writeHead(200, headers);
    const fileStream = fs.createReadStream(filePath, { highWaterMark: 256 * 1024 });
    fileStream.pipe(res);

    fileStream.on('error', (err) => {
      console.error('[Stream] Error streaming full file:', err.message);
      if (!res.headersSent) {
        res.status(500).end();
      }
    });

    req.on('close', () => {
      fileStream.destroy();
    });
  }
}

/**
 * Universal TV & Safari on-the-fly transmuxer
 * Repackages MKV / Dolby Vision containers into fragmented MP4 with 0% CPU loss (stream copy video, universal aac audio)
 */
function transmuxVideo(filePath, req, res) {
  if (!fs.existsSync(filePath)) {
    return res.status(404).send('Media file not found');
  }

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;

  // Handle Apple AVPlayer / CoreMedia Range probes to avoid error -12939
  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    const chunkSize = (end - start) + 1;

    // Fast-path for Apple AVPlayer 2-byte probe (Range: bytes=0-1)
    if (range === 'bytes=0-1') {
      res.writeHead(206, {
        'Content-Type': 'video/mp4',
        'Content-Range': `bytes 0-1/${fileSize}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': 2,
        'Access-Control-Allow-Origin': '*'
      });
      return res.end(Buffer.from([0x00, 0x00]));
    }

    res.writeHead(206, {
      'Content-Type': 'video/mp4',
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*'
    });
  } else {
    res.writeHead(200, {
      'Content-Type': 'video/mp4',
      'Content-Length': fileSize,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*'
    });
  }

  const startSeconds = parseFloat(req.query.start || '0');
  const ffmpeg = getFfmpegPath();

  const seekArgs = startSeconds > 0 ? ['-ss', startSeconds.toString()] : [];

  const args = [
    ...seekArgs,
    '-i', filePath,
    '-map', '0:v:0',
    '-map', '0:a:0?',
    '-c:v', 'copy',
    '-c:a', 'aac',
    '-b:a', '384k',
    '-sn',
    '-f', 'mp4',
    '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
    'pipe:1'
  ];

  const proc = spawn(ffmpeg, args, { stdio: ['ignore', 'pipe', 'ignore'] });

  proc.stdout.pipe(res);

  proc.on('error', (err) => {
    console.error('[Transmux] Process error:', err.message);
    if (!res.headersSent) {
      res.status(500).end();
    }
  });

  req.on('close', () => {
    try {
      proc.kill('SIGKILL');
    } catch (e) {}
  });
}

/**
 * Universal Apple Silicon hardware transcode for devices without 4K/HEVC decoders
 */
function transcodeVideo(filePath, req, res) {
  if (!fs.existsSync(filePath)) {
    return res.status(404).send('Media file not found');
  }

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    const chunkSize = (end - start) + 1;

    if (range === 'bytes=0-1') {
      res.writeHead(206, {
        'Content-Type': 'video/mp4',
        'Content-Range': `bytes 0-1/${fileSize}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': 2,
        'Access-Control-Allow-Origin': '*'
      });
      return res.end(Buffer.from([0x00, 0x00]));
    }

    res.writeHead(206, {
      'Content-Type': 'video/mp4',
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*'
    });
  } else {
    res.writeHead(200, {
      'Content-Type': 'video/mp4',
      'Content-Length': fileSize,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*'
    });
  }

  const startSeconds = parseFloat(req.query.start || '0');
  const ffmpeg = getFfmpegPath();

  const seekArgs = startSeconds > 0 ? ['-ss', startSeconds.toString()] : [];

  const args = [
    ...seekArgs,
    '-i', filePath,
    '-map', '0:v:0',
    '-map', '0:a:0?',
    '-vf', 'scale=-2:1080',
    '-c:v', 'h264_videotoolbox',
    '-b:v', '8M',
    '-c:a', 'aac',
    '-b:a', '256k',
    '-sn',
    '-f', 'mp4',
    '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
    'pipe:1'
  ];

  const proc = spawn(ffmpeg, args, { stdio: ['ignore', 'pipe', 'ignore'] });

  proc.stdout.pipe(res);

  proc.on('error', (err) => {
    console.error('[Transcode] Process error:', err.message);
    if (!res.headersSent) {
      res.status(500).end();
    }
  });

  req.on('close', () => {
    try {
      proc.kill('SIGKILL');
    } catch (e) {}
  });
}

module.exports = {
  streamVideo,
  transmuxVideo,
  transcodeVideo
};
