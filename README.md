# 🍿 Shapno — Mac Local Media Streaming Server

A fast, lightweight, and modern local media streaming server built with Node.js and Express that turns your Mac's `Media` folder into your private Netflix-like streaming service over your local Wi-Fi / Ethernet network.

---

## 🚀 Quick Start

### 1. Server Status
The server is currently running live on your Mac:
- **Local (on this Mac)**: [http://localhost:5050](http://localhost:5050)
- **Local Network (Smart TV / Phone / Tablet)**: `http://10.81.100.62:5050`

To start or restart the server manually from Terminal:
```bash
npm start
# or for auto-reload during development:
npm run dev
```

### 2. Stream on Any Device
- **On your Mac**: Open Safari, Chrome, or Brave and visit [http://localhost:5050](http://localhost:5050).
- **On your Phone / Tablet**: Connect to the same Wi-Fi, open your Camera, and scan the QR code from the Mac terminal or the web app's **"Connect TV / Mobile"** button.
- **On your Smart TV** (Android TV, Apple TV, LG WebOS, Samsung Tizen, Fire TV):
  1. Open your TV's built-in web browser (Chrome, Silk, Safari, WebOS browser).
  2. Enter `http://10.81.100.62:5050`
  3. Bookmark the page or add it to your TV Home Screen for 1-click access!

---

## 📁 How to Organize Movies & TV Series

Just drag and drop your media files or zip archives into the **`Media`** folder:

```text
/Volumes/Office Files/Local_Server_Movies/Media/
│
├── Movies/
│   ├── Spider-Man Brand New Day.mkv
│   ├── TOXiC.mkv
│   └── Blue.mkv
│
└── Series/
    ├── Friends Sex and Games/               <-- Folder name = Series Name!
    │   ├── Friends.Sex.and.Games.S01E01.mkv
    │   ├── Friends.Sex.and.Games.S01E02.mkv
    │   └── ...
    │
    └── Bachelor Point/                      <-- Folder name = Series Name!
        └── Bachelor.Point.Season.04.E77.mkv
```

### 🎬 Series Rules & Features:
1. **Folder Name = Series Name**: The name of the folder directly inside `Media/Series/` is automatically used as the title of the TV Series (e.g. `Friends Sex and Games`, `Bachelor Point`).
2. **Random Thumbnail**: The series card thumbnail dynamically picks a random episode thumbnail so the UI stays fresh and vibrant.
3. **Click to View Episodes**: Clicking on any series card opens the **Episodes Explorer Modal** showing all episodes sequentially sorted, with individual episode thumbnails, file sizes, subtitle indicators, and direct 1-click streaming.
4. **All Media Sectioned**: In the "All Media" view, movies and TV series are categorized into distinct sections (🍿 **Movies** and 📺 **TV Series**) with separate counts and grid cards.

---

## ✨ Features & Architecture

- 🏎️ **Instant Range Streaming (HTTP 206 Partial Content)**: Seek and scrub forward/backward without lag or buffering.
- ⚡ **Lossless Real-Time MKV Transmuxing**: Plays large MKV containers smoothly on Apple TV, Safari, and Smart TV browsers that don't natively support raw MKV.
- 📺 **TV Remote D-Pad Navigation**: Fully navigable using TV remote arrow keys, Enter to play, and Back / Escape to close modals and exit player.
- 🎨 **Obsidian & Champagne Gold Aesthetic**: Professional, cinematic dark palette inspired by Apple TV+ and Cannes cinema.
- 💬 **Smart Subtitles**: On-the-fly conversion of external `.srt` subtitles and automatic extraction of embedded MKV/MP4 subtitle tracks to WebVTT.
- 🔄 **Real-Time Live Sync (SSE)**: Drop a new movie or series into `Media/`, and it immediately shows up across all TVs and phones without refreshing the page.
- 📦 **Automatic Zip Extraction**: Dropped zip files are automatically unpacked into the media directory.
- ⏱️ **Resume Playback**: Remembers playback progress so you can resume where you stopped.
