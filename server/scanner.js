const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const VIDEO_EXTENSIONS = new Set([
  '.mp4', '.mkv', '.webm', '.mov', '.avi', '.m4v',
  '.flv', '.wmv', '.ts', '.m2ts', '.mts', '.mpg',
  '.mpeg', '.vob', '.3gp', '.rmvb', '.divx', '.asf',
  '.ogv', '.f4v'
]);
const SUBTITLE_EXTENSIONS = new Set(['.srt', '.vtt']);

function generateId(relativePath) {
  return crypto.createHash('md5').update(relativePath).digest('hex').slice(0, 12);
}

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
}

function parseMediaTitle(fileName, parentDirName) {
  const ext = path.extname(fileName);
  let base = path.basename(fileName, ext);

  // Strip leading tracker/site prefixes (e.g., "Rtally.Xyz - ", "YTS.MX - ")
  base = base.replace(/^([a-z0-9\-]+\.(xyz|com|org|net|to|mx|sx|cc|me|app)\s*[\-\_\s]+)/i, '');

  // Detect Series pattern: S01E02, S05E121-128, 1x02
  const seasonMatch = base.match(/[Ss](\d+)[Ee](\d+)(?:[-–]\d+)?/) || base.match(/(\d+)x(\d+)/);
  let isSeries = false;
  let season = 1;
  let episode = 1;

  if (seasonMatch) {
    isSeries = true;
    season = parseInt(seasonMatch[1], 10);
    episode = parseInt(seasonMatch[2], 10);
  } else if (parentDirName && /season\s*\d+/i.test(parentDirName)) {
    isSeries = true;
    const sMatch = parentDirName.match(/season\s*(\d+)/i);
    season = sMatch ? parseInt(sMatch[1], 10) : 1;
    const epMatch = base.match(/episode\s*(\d+)/i) || base.match(/\bE?(\d{1,3})\b/);
    episode = epMatch ? parseInt(epMatch[1], 10) : 1;
  }

  // Detect Year
  const yearMatch = base.match(/[\(\[]((?:19|20)\d{2})[\)\]]/) || base.match(/\b((?:19\d{2}|20[0-2]\d))\b/);
  const year = yearMatch ? yearMatch[1] : null;

  // Clean title for display
  let cleanName = base;
  if (seasonMatch) {
    cleanName = base.substring(0, seasonMatch.index);
  } else if (yearMatch) {
    cleanName = base.substring(0, yearMatch.index);
  }

  // Remove bracketed or parenthesized tags like [Bengali], [1080p]
  cleanName = cleanName.replace(/\[[^\]]*\]/g, ' ').replace(/\([^\)]*\)/g, ' ');

  // Strip common release tags
  cleanName = cleanName
    .replace(/[._\-]/g, ' ')
    .replace(/\b(1080p|720p|4k|2160p|uhd|bluray|blu-ray|web-dl|webrip|hdr|dvdrip|h264|x264|h265|x265|hevc|aac|dts)\b/gi, '')
    .replace(/[\[\]\(\)\{\}]/g, '')
    .replace(/\s+/g, ' ')
    .trim();

  if (!cleanName) {
    cleanName = base;
  }

  return {
    cleanTitle: cleanName,
    rawName: base,
    isSeries,
    season,
    episode,
    year,
    extension: ext.toLowerCase()
  };
}

/**
 * Scan media directory and organize into Movies and TV Series (by Series Folder)
 */
function scanDirectory(mediaRoot) {
  const result = {
    movies: [],
    series: [],
    allFlat: []
  };

  if (!fs.existsSync(mediaRoot)) {
    fs.mkdirSync(mediaRoot, { recursive: true });
    return result;
  }

  const seriesMap = new Map(); // seriesName -> Series Object
  const flatItems = [];

  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });

    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue; // ignore hidden files
      const fullPath = path.join(currentDir, entry.name);

      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.isFile()) {
        const ext = path.extname(entry.name).toLowerCase();
        if (VIDEO_EXTENSIONS.has(ext)) {
          const stats = fs.statSync(fullPath);
          const relativePath = path.relative(mediaRoot, fullPath);
          const pathSegments = relativePath.split(path.sep);
          const parentDir = path.basename(path.dirname(fullPath));
          const parsed = parseMediaTitle(entry.name, parentDir);

          // Subtitle check
          const subtitles = [];
          const dirFiles = fs.readdirSync(currentDir);
          const baseNameWithoutExt = path.basename(entry.name, ext);

          for (const df of dirFiles) {
            const dfExt = path.extname(df).toLowerCase();
            if (SUBTITLE_EXTENSIONS.has(dfExt)) {
              if (df.startsWith(baseNameWithoutExt) || dirFiles.filter(f => VIDEO_EXTENSIONS.has(path.extname(f).toLowerCase())).length === 1) {
                subtitles.push({
                  name: df,
                  fullPath: path.join(currentDir, df),
                  ext: dfExt,
                  label: df.includes('.en.') ? 'English' : path.basename(df, dfExt),
                  isEmbedded: false
                });
              }
            }
          }

          // Embedded Subtitle Detection in MKV/MP4
          if (subtitles.length === 0 && (ext === '.mkv' || ext === '.mp4')) {
            try {
              const ffprobePath = fs.existsSync('/opt/homebrew/bin/ffprobe') ? '/opt/homebrew/bin/ffprobe' : 'ffprobe';
              const probeOut = execFileSync(ffprobePath, [
                '-v', 'error',
                '-select_streams', 's',
                '-show_entries', 'stream=index:stream_tags=language,title',
                '-of', 'json',
                fullPath
              ], { encoding: 'utf8', timeout: 3000 });
              const probeData = JSON.parse(probeOut);
              if (probeData.streams && probeData.streams.length > 0) {
                probeData.streams.forEach((st, idx) => {
                  const lang = st.tags?.language ? st.tags.language.toUpperCase() : 'Embedded';
                  const title = st.tags?.title || `Track ${idx + 1}`;
                  subtitles.push({
                    name: `embedded_${idx}`,
                    isEmbedded: true,
                    trackIndex: idx,
                    ext: '.vtt',
                    label: `${lang} Subtitles (${title})`
                  });
                });
              }
            } catch (e) {}
          }

          const fileId = generateId(relativePath);

          // Check if this file belongs to a Series:
          // Rule 1: Located under 'Series/' folder (e.g. Series/<SeriesFolderName>/...)
          // The Series Name is strictly the folder name directly under Series/!
          let isSeries = false;
          let seriesFolderName = null;

          if (pathSegments.length >= 2 && pathSegments[0].toLowerCase() === 'series') {
            isSeries = true;
            seriesFolderName = pathSegments[1]; // The exact folder name!
          } else if (parsed.isSeries) {
            isSeries = true;
            // If in a subfolder, use that subfolder as series name, else parsed clean title
            seriesFolderName = (pathSegments.length > 1) ? pathSegments[0] : parsed.cleanTitle;
          }

          const lowerName = entry.name.toLowerCase();
          const is4K = lowerName.includes('2160p') || lowerName.includes('4k') || lowerName.includes('uhd');
          const isDolbyVision = lowerName.includes('.dv.') || lowerName.includes('dovi') || lowerName.includes('dolby.vision') || lowerName.includes('dolby vision');
          const isHDR = lowerName.includes('hdr') || lowerName.includes('hdr10') || isDolbyVision;

          const mediaItem = {
            id: fileId,
            title: isSeries ? `Episode ${parsed.episode}` : parsed.cleanTitle,
            cleanTitle: parsed.cleanTitle,
            fileName: entry.name,
            fullPath,
            relativePath,
            sizeBytes: stats.size,
            sizeFormatted: formatBytes(stats.size),
            format: ext.replace('.', '').toUpperCase(),
            type: isSeries ? 'series' : 'movie',
            seriesName: seriesFolderName,
            season: parsed.season,
            episode: parsed.episode,
            year: parsed.year,
            is4K,
            isDolbyVision,
            isHDR,
            hasSubtitles: subtitles.length > 0,
            subtitles: subtitles.map(s => ({
              label: s.label,
              ext: s.ext,
              isEmbedded: !!s.isEmbedded,
              trackIndex: s.trackIndex || 0,
              name: s.name
            })),
            addedAt: stats.mtime
          };

          flatItems.push(mediaItem);

          if (isSeries) {
            if (!seriesMap.has(seriesFolderName)) {
              seriesMap.set(seriesFolderName, {
                id: generateId(`series_${seriesFolderName}`),
                title: seriesFolderName, // Folder name is series name!
                folderName: seriesFolderName,
                type: 'series',
                totalSizeBytes: 0,
                format: mediaItem.format,
                year: parsed.year,
                episodes: []
              });
            }
            const sObj = seriesMap.get(seriesFolderName);
            sObj.totalSizeBytes += stats.size;
            sObj.episodes.push(mediaItem);
          } else {
            result.movies.push(mediaItem);
          }
        }
      }
    }
  }

  walk(mediaRoot);

  // Process Series list
  for (const [sName, sObj] of seriesMap.entries()) {
    // Sort episodes sequentially by Season & Episode number ascending
    sObj.episodes.sort((a, b) => {
      if ((a.season || 1) !== (b.season || 1)) {
        return (a.season || 1) - (b.season || 1);
      }
      return (a.episode || 1) - (b.episode || 1);
    });

    sObj.episodesCount = sObj.episodes.length;
    sObj.totalSizeFormatted = formatBytes(sObj.totalSizeBytes);

    // Pick a random episode thumbnail for the series card to keep it dynamic and fresh!
    const randomIndex = Math.floor(Math.random() * sObj.episodes.length);
    sObj.randomEpisodeId = sObj.episodes[randomIndex].id;
    sObj.thumbnailUrl = `/api/thumbnail/${sObj.randomEpisodeId}`;

    // Get count of unique seasons
    const seasonsSet = new Set(sObj.episodes.map(e => e.season || 1));
    sObj.seasonsCount = seasonsSet.size;

    result.series.push(sObj);
  }

  // Sort Movies by newest modified first
  result.movies.sort((a, b) => new Date(b.addedAt) - new Date(a.addedAt));

  // Sort Series by newest episode added
  result.series.sort((a, b) => {
    const aLatest = Math.max(...a.episodes.map(e => new Date(e.addedAt).getTime()));
    const bLatest = Math.max(...b.episodes.map(e => new Date(e.addedAt).getTime()));
    return bLatest - aLatest;
  });

  result.allFlat = flatItems;
  return result;
}

module.exports = {
  scanDirectory,
  generateId,
  parseMediaTitle,
  formatBytes
};
