# VHS FX (PowerShell) — README

Applies a **VHS look** to both video and audio using **FFmpeg** and **SoX**, then muxes the result into an AVI container (UTVideo + PCM).

> **Strongly recommended:** Run this script with **PowerShell 7 (pwsh)** inside **Windows Terminal**. Windows PowerShell 5.x may show Unicode/emoji glitches and has poorer cross‑platform behavior. PS7 + Windows Terminal avoids those issues.

---

## ✨ Features
- VHS‑style **video**: YUV plane separation, heavy down/upscales for chroma bleed, desaturation, grain, and subtle horizontal jitter.
- VHS‑style **audio**: original audio mixed with **brown noise** and a **4 kHz low‑pass** to mimic tape bandwidth.
- Lossless intermediate: **UTVideo** (video) + **PCM float** (audio) → easy to transcode later.
- **Single file** mode or **batch** mode via JSON list.
- Automatic cleanup of temporary files.

---

## 📦 Requirements
- **Windows 10/11**
- **PowerShell 7+** (pwsh) — *strongly recommended*, especially because the script prints emojis.
- **Windows Terminal** — recommended for proper Unicode rendering.
- **FFmpeg** (includes `ffprobe`) in your `PATH`.
- **SoX** in your `PATH`.

Verify installations:
```powershell
ffmpeg -version
ffprobe -version
sox --version
$PSVersionTable.PSVersion
```

---

## 🗂️ Set your working folder
The script uses several paths with the placeholder `<<YOUR_VIDEOS_FOLDER>>`. Replace it with an existing folder for temps and outputs, e.g.:

```powershell
$global:vhsFile   = "C:\Videos\work\vhs.avi"
$global:wavFile   = "C:\Videos\work\audio.wav"
$global:wavFxFile = "C:\Videos\work\vhs.wav"
$global:noise     = "C:\Videos\work\noise.wav"
$global:mix       = "C:\Videos\work\mix.wav"
```

The **final output** defaults to: `<<YOUR_VIDEOS_FOLDER>>\<basename>.avi`.

> JSON on Windows uses doubled backslashes: `C\\Videos\\clip.mp4`.

---

## 🚀 Quick start

### 1) Single file
```powershell
# In PowerShell 7 (pwsh)
.\vhs.ps1 -InputPath "C:\Videos\clip.mp4"
```
If you omit `-InputPath`, the script will prompt for it (drag‑and‑drop also works in some shells).

### 2) Batch mode (JSON list)
Create a JSON file with an **array of absolute paths**:
```json
[
  "C\\Videos\\clip1.mp4",
  "D\\Captures\\session.mkv"
]
```
Run:
```powershell
.hs.ps1 -JsonPath "C:\Videos\list.json"
```
The script will iterate the list and process each video.

---

## ⚙️ Parameters
- `-InputPath <string>`: path to a single input video.
- `-JsonPath  <string>`: path to a JSON file containing a list of video paths.

If both are omitted, you’ll be prompted for a path.

---

## 🧪 Processing pipeline

### Step 0 — **VHS FX (video)**
`ffmpeg -filter_complex` pipeline:
- Split into **Y/U/V** with `extractplanes`.
- Luma (Y) down/up: `scale=768:1080` → `scale=1920:1080`.
- Chroma (U/V) down/up: `scale=120:540` → `scale=960:540`.
- Recombine to **yuv420p** via `mergeplanes`.
- Tone & texture: `eq=saturation=0.75`, `noise=alls=5`, and a mild **horizontal jitter** in luma with `geq` + `random()`.

**Outputs:**
- `vhs.avi` (video only, **UTVideo**, tagged as `bt709`)
- `audio.wav` (PCM extracted from the source)

### Step 1 — **VHS FX (audio)**
Using **SoX**:
1) Synthesize **brown noise** for the full duration (queried via `ffprobe`). 48 kHz / 32‑bit float / stereo.
2) Mix original audio + noise with gains `inVol` and `outVol`.
3) Apply **low‑pass** at **4 kHz**.

**Output:** `vhs.wav`.

### Step 2 — **Final mux**
Combine `vhs.avi` (video) + `vhs.wav` (audio) without re‑encoding (`-c copy`) to:
```
<<YOUR_VIDEOS_FOLDER>>\<basename>.avi
```
> The `<basename>` is sanitized: illegal characters `:*?"<>|` become `-`.

### Step 3 — **Cleanup**
Delete temporaries: `noise.wav`, `mix.wav`, `vhs.avi`, `vhs.wav`, `audio.wav`.

---

## 🔧 Default constants

| Variable          | Default     | Notes                                  |
|-------------------|-------------|----------------------------------------|
| `sampleRate`      | `48000`     | Audio sample rate (Hz)                 |
| `bitDepth`        | `32`        | Float processing depth                 |
| `channels`        | `2`         | Stereo                                 |
| `lowPassFreq`     | `4000`      | Low‑pass cutoff (Hz)                   |
| `inVol`           | `1.0`       | Gain for original track                |
| `outVol`          | `0.077`     | Gain for noise track                   |
| `db`              | `-22.75`    | For `dbVolume` computation             |
| `dbVolume`        | `10^(dB/20)`| Linear factor derived from `db`        |
| `vCodec`          | `utvideo`   | Lossless intermediate                  |
| `aCodec`          | `pcm_f32le` | Float PCM                              |
| `pixFmt`          | `yuv420p`   | Pixel format                           |
| `vidColorspace`   | `bt709`     | Colorimetry signaled on output         |

> You can fine‑tune the FFmpeg filter in `$global:ffmpegFilter` (saturation, noise amount, jitter magnitude, etc.).

---

## 🧰 Post‑processing (optional)
Lossless intermediates are **large**. Transcode after inspection:

**To H.264 (high quality):**
```powershell
ffmpeg -i "final.avi" -c:v libx264 -crf 16 -preset slow -c:a aac -b:a 192k "final_h264.mp4"
```
**To H.265/HEVC:**
```powershell
ffmpeg -i "final.avi" -c:v libx265 -crf 20 -preset slow -c:a aac -b:a 192k "final_hevc.mp4"
```
**Remux to MKV (no re‑encode):**
```powershell
ffmpeg -i "final.avi" -c copy "final.mkv"
```

---

## 🧯 Troubleshooting
- **`ffprobe` returns `N/A`** → Source file or container is problematic. Try: `ffmpeg -i input -c copy fixed.mkv`, then re‑run the script.
- **`ffmpeg`/`sox` not recognized** → Add to `PATH` or call with absolute paths.
- **Paths with spaces** → Always wrap in quotes: `"C:\My Videos\clip.mp4"`.
- **Emoji/Unicode look broken** → Use **PowerShell 7** in **Windows Terminal**.
- **Colorimetry looks off in some players** → Remux to MKV: `ffmpeg -i final.avi -c copy final.mkv`.

---

## 🧭 Files produced (temps & output)
```
<<YOUR_VIDEOS_FOLDER>>\
├─ vhs.avi       # Video w/ VHS look (UTVideo, video‑only)
├─ audio.wav     # Original audio (extracted)
├─ noise.wav     # Brown noise (synthesized)
├─ mix.wav       # Mixed original+noise
├─ vhs.wav       # Final audio after low‑pass
└─ <basename>.avi  # FINAL FILE (streams copied)
```
Temporaries are deleted at the end of the run.

---

## 📜 License
**MIT License** — feel free to use, modify, and distribute.

---

## 🙌 Notes & ideas
- Prefer **PS7 + Windows Terminal** for the best experience.
