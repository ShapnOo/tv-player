# 📺 Shapno TV — Android TV App (4K UHD)

Dedicated, clean, high-performance Android TV application specifically tailored and optimized for the **Hisense 50A6F3 50-Inch 4K UHD TV (Google TV / Android TV)** and other Android TV devices.

---

## 🌟 Key Features

1. **Direct Local Network Streaming**:
   - Directly connects to your MacBook Pro's streaming server (`http://10.81.100.62:5050`).
   - Streams 4K UHD MKV, MP4, and HEVC/H.264 files without lag or stutter.
   - Supports HTTP Range seeking (fast forward / rewind ±10 seconds).

2. **Full TV Remote (D-Pad) Navigation**:
   - 100% remote control friendly: `Up`, `Down`, `Left`, `Right`, `Center/OK`, and `Back`.
   - Netflix / Apple TV inspired focus animations with glowing emerald/cyan borders and elevation.

3. **Curated Categorization**:
   - 🍿 **Movies**: High-res poster thumbnails, 4K UHD badges, and file sizes.
   - 📺 **TV Series**: Folder names are used as series titles (e.g. *Friends Sex and Games*, *Bachelor Point*).
   - Dedicated Series Detail Screen with episode selector cards, season counter, and instant play.

4. **Hardware-Accelerated 4K Player**:
   - Native ExoPlayer video engine with HDR / 4K hardware decoding.
   - Wakelock enabled: prevents your 50" TV screen from dimming or sleeping during movies.
   - TV Remote shortcuts:
     - **OK / Select**: Play / Pause
     - **Right Arrow**: Seek +10s forward
     - **Left Arrow**: Seek -10s backward
     - **Up / Down Arrow**: Show/hide on-screen controls overlay
     - **Back**: Exit player back to details / home

5. **Instant IP Switcher & Discovery**:
   - If your MacBook's Wi-Fi IP changes, click the top Wi-Fi pill to change the server address right from the TV remote.

---

## 🚀 How to Install on Hisense 50A6F3 4K TV

### Method 1: USB Flash Drive (Fastest & Simplest)
1. Copy the generated `Shapno-AndroidTV.apk` to a USB flash drive.
2. Plug the USB flash drive into the USB port on your Hisense TV.
3. On your TV, open the built-in **Media / File Manager** (or install **File Commander** / **Cx File Explorer** from Google Play Store on the TV).
4. Navigate to the USB drive and click **`Shapno-AndroidTV.apk`** to install.
5. If prompted, toggle "Allow installation from unknown sources".
6. Open **Shapno TV** from your Google TV apps row!

### Method 2: "Send Files to TV" (Wireless)
1. On your Hisense TV, open the Google Play Store and install **"Send Files to TV"** and **"File Commander"**.
2. Install **"Send Files to TV"** on your phone (or use Mac Bluetooth / web).
3. Send `Shapno-AndroidTV.apk` to the TV.
4. In **File Commander** on the TV, go to `Downloads`, click `Shapno-AndroidTV.apk`, and tap Install.

### Method 3: Wireless ADB (Developer Mode)
1. On your Hisense TV: Go to **Settings** → **System** → **About** → Click **Android TV OS build** 7 times to enable Developer Mode.
2. Go to **Settings** → **System** → **Developer Options** → Enable **USB Debugging** & **Wireless Debugging**.
3. Note your TV's IP address (e.g. `10.81.100.XX`).
4. In your Mac terminal:
   ```bash
   adb connect <YOUR-TV-IP>:5555
   adb install "Shapno-AndroidTV.apk"
   ```

---

## 🛠️ App Architecture
- **Framework**: Flutter with Leanback TV optimization
- **Video Engine**: ExoPlayer with Media3 Direct HTTP Range Streaming
- **Networking**: `http` REST API + local caching
- **Platform**: Android TV / Google TV (minSdk 21, targetSdk 35)
