# CCLight App Store Screenshots

Six marketing screenshot variants at 2880×1800 (Retina 1440×900).

| File | State | Halo | Key message |
|------|-------|------|-------------|
| v1.html | Working | Amber | Hero — "Your notch tells you when Claude is thinking." |
| v2.html | Multi-session | Amber/Green/Amber/White | "Four sessions. One glance." |
| v3.html | Waiting | Green | "Green means it's your turn." |
| v4.html | Working | Amber | "Designed to live in your peripheral vision." |
| v5.html | Working | Amber | "Drill in when you need to. Otherwise, never." |
| v6.html | Idle | White | "No network. No telemetry. Just light." |

---

## Rendering to PNG

### Option A — Headless Chrome (recommended)

Requires Google Chrome or Chromium installed at the standard macOS path.

```bash
# Render a single file
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --headless=new \
  --disable-gpu \
  --screenshot="$(pwd)/out/v1.png" \
  --window-size=2880,1800 \
  --hide-scrollbars \
  "file://$(pwd)/v1.html"
```

```bash
# Render all six variants at once
mkdir -p out

for n in 1 2 3 4 5 6; do
  /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
    --headless=new \
    --disable-gpu \
    --screenshot="$(pwd)/out/v${n}.png" \
    --window-size=2880,1800 \
    --hide-scrollbars \
    "file://$(pwd)/v${n}.html"
  echo "Rendered v${n}.png"
done
```

Output PNGs land in `marketing/screenshots/out/`.

### Option B — Chromium (Homebrew)

```bash
brew install chromium

for n in 1 2 3 4 5 6; do
  chromium \
    --headless \
    --disable-gpu \
    --screenshot="$(pwd)/out/v${n}.png" \
    --window-size=2880,1800 \
    --hide-scrollbars \
    "file://$(pwd)/v${n}.html"
done
```

### Option C — webkit2png (fallback, macOS only)

webkit2png ships with Xcode Command Line Tools on older macOS versions.
It uses the system WebKit engine, which will render CSS accurately.

```bash
pip3 install webkit2png   # or: pip install webkit2png

for n in 1 2 3 4 5 6; do
  webkit2png \
    --width=2880 \
    --height=1800 \
    --scale=1 \
    --fullsize \
    --filename="out/v${n}" \
    "file://$(pwd)/v${n}.html"
done
```

Note: webkit2png appends `-full.png` to the filename, so output will be `out/v1-full.png` etc.

### Option D — Puppeteer (Node.js)

```bash
npx puppeteer-core screenshot \
  --browser chrome \
  --url "file://$(pwd)/v1.html" \
  --viewport 2880x1800 \
  --output out/v1.png
```

Or use a short Node script:

```js
// render-all.mjs
import puppeteer from 'puppeteer';
import { resolve } from 'path';
import { mkdirSync } from 'fs';

mkdirSync('out', { recursive: true });

const browser = await puppeteer.launch({ args: ['--no-sandbox'] });
const page = await browser.newPage();
await page.setViewport({ width: 2880, height: 1800, deviceScaleFactor: 1 });

for (const n of [1, 2, 3, 4, 5, 6]) {
  const file = `file://${resolve(`v${n}.html`)}`;
  await page.goto(file, { waitUntil: 'networkidle0' });
  await page.screenshot({ path: `out/v${n}.png`, fullPage: false });
  console.log(`Rendered v${n}.png`);
}

await browser.close();
```

```bash
npm install puppeteer
node render-all.mjs
```

---

## Producing 1440×900 versions (non-Retina App Store size)

App Store Connect accepts both 2880×1800 (Retina) and 1440×900 (non-Retina).
Downscale the PNGs with `sips` (built into macOS):

```bash
mkdir -p out/1440

for n in 1 2 3 4 5 6; do
  sips --resampleWidth 1440 "out/v${n}.png" --out "out/1440/v${n}.png"
done
```

Or with ImageMagick:

```bash
brew install imagemagick

for n in 1 2 3 4 5 6; do
  convert "out/v${n}.png" -resize 1440x900 "out/1440/v${n}.png"
done
```

---

## Output file layout

```
marketing/screenshots/
├── mockup-template.html   ← reusable base template with query-string config
├── v1.html                ← Hero / amber WORKING
├── v2.html                ← Multi-session
├── v3.html                ← Green WAITING + terminal
├── v4.html                ← Ambient / editor in foreground
├── v5.html                ← Menu dropdown
├── v6.html                ← Privacy / local-first
├── README.md              ← this file
└── out/                   ← generated PNGs (git-ignored, create after rendering)
    ├── v1.png  …  v6.png          (2880×1800)
    └── 1440/
        └── v1.png  …  v6.png     (1440×900)
```

Add `marketing/screenshots/out/` to `.gitignore` if you do not want to commit the rendered PNGs.

---

## App Store upload checklist

- Format: PNG, no alpha channel required (App Store Connect accepts RGBA)
- Minimum 1 screenshot, maximum 10 per locale
- For macOS: required sizes are 1280×800 or 2560×1600 (the 1440/2880 sizes are alternative)
- Screenshots must not be device frames (macOS App Store does not add frames automatically for screenshots submitted as raw images — use as-is or add a subtle device frame in post)
- Upload order in App Store Connect determines display order — lead with v1 (hero)
