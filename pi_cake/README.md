# Capybara Judge System

## English

### Overview

Capybara Judge System is an ESP32 judging environment. The judge script handles flashing, board detection, serial communication, scoring, and result reporting automatically.

### What You Need to Do

1. Create a virtual environment.
2. Activate the virtual environment.
3. Install dependencies from `requirements.txt`.
4. Edit only the `TODO` block inside `implementation/pi.cpp`.

Do not modify files outside the allowed `TODO` area unless the project instructions explicitly say otherwise.

### Installation

Create and activate a virtual environment, then install the dependencies:

```bash
python -m venv venv
```

Activate it. **On Windows, use CMD** — PowerShell's `Activate.ps1` is often blocked by
"running scripts is disabled on this system" (open CMD in the folder: right-click → Open in
Terminal → type `cmd`):

```bash
# Windows CMD  (recommended)
venv\Scripts\activate.bat

# Windows PowerShell  (only if script execution is enabled)
.\venv\Scripts\Activate.ps1

# Linux / macOS
source venv/bin/activate
```

Install requirements:

```bash
pip install -r requirements.txt
```

### Run

After the environment is ready, run the judge normally. The judge will perform flashing and evaluation on its own:

```bash
python capybara_judge.py
```

To print detailed diffs for wrong answers:

```bash
python capybara_judge.py --show-diff
```

### Time Limits

Current case limits:

* `pi1`: 50.0 seconds
* `pi2`: 150.0 seconds
* `pi3`: 150.0 seconds

These are total case limits, not per-task limits.

### Workflow

* The judge detects the ESP32 automatically.
* The judge flashes the project automatically.
* The judge waits for the board ready signal.
* The judge sends tasks through serial.
* The judge checks each response against the expected answer.
* The judge prints scores and final comments.

### Important Rules

* Only edit `implementation/pi.cpp`.
* Only edit the `TODO` section.
* Do not change unrelated files.
* Do not manually handle flashing or evaluation steps; the judge does that automatically.

### Output

The judge prints:

* per-level accuracy
* per-level execution time
* weighted score
* final score
* final title and comment

---

## 中文

### 簡介

Capybara Judge System 是一個 ESP32 評測環境。評測腳本會自動完成燒錄、裝置偵測、序列通訊、計分與結果輸出。

### 使用者需要做的事情

1. 建立虛擬環境。
2. 進入虛擬環境。
3. 根據 `requirements.txt` 安裝相依套件。
4. 只修改 `implementation/pi.cpp` 裡面的 `TODO` 區塊。

除非專案另外明確要求，否則不要修改 `TODO` 區塊以外的內容。

### 安裝方式

先建立並啟用虛擬環境，再安裝依賴套件：

```bash
python -m venv venv
```

啟用虛擬環境。**Windows 請用 CMD** — PowerShell 的 `Activate.ps1` 常被
「running scripts is disabled on this system」擋掉（在資料夾按右鍵 → Open in Terminal → 輸入 `cmd`）：

```bash
# Windows CMD（建議）
venv\Scripts\activate.bat

# Windows PowerShell（僅在指令碼執行已開啟時）
.\venv\Scripts\Activate.ps1

# Linux / macOS
source venv/bin/activate
```

安裝需求套件：

```bash
pip install -r requirements.txt
```

### 執行方式

環境準備好之後，直接執行 judge。燒錄與評測都會由程式自動完成：

```bash
python capybara_judge.py
```

若要在答案錯誤時顯示更詳細的 diff：

```bash
python capybara_judge.py --show-diff
```

### 時限設定

目前各 case 的總時限如下：

* `pi1`: 50.0 秒
* `pi2`: 150.0 秒
* `pi3`: 150.0 秒

這些是整個 case 的總時限，不是每一題的時限。

### 執行流程

* judge 會自動偵測 ESP32。
* judge 會自動燒錄專案。
* judge 會等待板子就緒訊號。
* judge 會透過序列埠送出測資。
* judge 會將回傳結果與標準答案比對。
* judge 會輸出分數與最後評語。

### 重要規則

* 只允許修改 `implementation/pi.cpp`。
* 只允許修改 `TODO` 區塊。
* 不要改動其他無關檔案。
* 不需要手動燒錄或手動做評測，這些都由 judge 自動執行。

### 輸出內容

程式結束時會顯示：

* 各層級正確率
* 各層級執行時間
* 加權分數
* 最終總分
* 最後稱號與評語
