# codpy-s4 Doctor 🩺

A **fallback** for the workshop setup. The presentation slides are the main instructions —
this script is the safety net for when a machine is in some unknown/broken state. It checks
**every stage from `uv` installation through ESP32 connectivity**, tells you exactly what is
wrong, and **offers to auto-fix each problem it finds**.

> 這是工作坊安裝流程的「**備援**」。簡報才是主要步驟；當電腦狀態不明或壞掉時，用這支腳本
> 從 `uv` 安裝一路檢查到 ESP32 連線，並在偵測到問題時**詢問是否自動修復**。

## How to run / 怎麼跑

1. Plug in your ESP32 (use a **data** USB cable, not charge-only).
2. In the file explorer, open the `doctor` folder and **double-click `doctor.bat`**.
   - 或在資料夾按右鍵 → 在終端機開啟 → 輸入 `doctor\doctor.bat`。
3. For each problem found it asks `Attempt auto-fix? [Y/n]`, applies the fix, then re-checks.

You may see **one UAC prompt** — only if a USB-serial driver needs installing.

## Modes / flags

| Flag | What it does |
|---|---|
| *(none)* | Interactive: prompts before each fix (default). |
| `-DiagnoseOnly` | Report only — changes **nothing**. Good for a TA to inspect a machine. |
| `-Fix` | Apply every fix **without** prompting. |
| `-IncludeBuild` | Also run the PlatformIO smoke build (slow; downloads the Xtensa toolchain). |
| `-PatchRenderPort` | Auto-rewrite `fractal/render.py`'s `SERIAL_PORT` to the detected COM port. |
| `-SkipDrivers` | Skip the USB-driver and ESP32 stages. |
| `-Port COM5` | Force a specific COM port for the ESP32 handshake. |
| `-GrandDir <path>` | Repo root (defaults to the parent of this `doctor/` folder). |

Examples:

```bat
doctor\doctor.bat                 rem interactive
doctor\doctor.bat -DiagnoseOnly   rem check only
doctor\doctor.bat -Fix            rem fix everything unattended
```

## What each stage checks

| # | Stage | Auto-fix it offers |
|---|---|---|
| 1 | `uv` + Python 3.12 on PATH | install uv (`astral.sh/uv/install.ps1`) + `uv python install 3.12` |
| 2 | `git` on PATH | `winget install Git.Git`, fallback PortableGit |
| 3 | Grand repo intact (`.git`, `pi_cake/`, `fractal/`) | clone only into an empty target — **never overwrites your edits** |
| 4 | `pi_cake` / `fractal` venvs + imports (`serial,esptool` / `serial,pygame`) | `uv venv` + `uv pip install -r requirements.txt` |
| 5 | USB-serial driver + COM port (CH340 / CP210x / FTDI / Espressif; problem code 28) | install CP210x driver via `pnputil`; CH340 from bundled `drivers/` |
| 6 | **ESP32 handshake** — actually talks to the chip (`esptool read_mac`) | advisory (cable / BOOT / port-busy) + offer to patch `render.py` port |
| 7 | *(opt-in)* PlatformIO smoke build | — verification only |

Exit codes: `0` all good · `2` warnings only · `1` problems remain.
Logs are written to `doctor/logs/doctor_<timestamp>.log` — attach the newest one when asking for help.

## Manual test matrix (for maintainers)

Run on Windows with an ESP32 attached:

1. **Clean machine** → stages 1–6 FAIL/WARN → accept fixes → re-run → all OK.
2. **Already set up** → all OK on the first pass.
3. **Board unplugged** → Stage 5 WARN + Stage 6 WARN/SKIP; plug in → re-run → OK.
4. `-DiagnoseOnly` makes **no** changes; `-Fix` runs fully unattended.

> This container that generated the script is Linux (no PowerShell), so it was authored and
> reviewed statically. Run `Invoke-ScriptAnalyzer doctor.ps1` on a Windows box for a lint pass.

## Offline CH340 drivers

If your network can't reach WCH, drop the unpacked CH340 `.inf` (and its `.sys`/`.cat`) into
`doctor/drivers/` before the workshop. The doctor will pick them up automatically in Stage 5.
