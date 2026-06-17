# Codpy S4 — ESP32 作業包 (Assignment Pack)

> ⚠️ Placeholder — full assignment write-up TBD.

兩個 ESP32 作業，一個 repo。Two ESP32 assignments in one repo.

| 資料夾 | 是什麼 | 你要做什麼 |
|---|---|---|
| [`pi_cake/`](./pi_cake) | 卡皮巴拉評分機 — π 數字題 (capybara judge) | 填 `implementation/pi{1,2,3}/src/pi*.cpp` 的 TODO，跑 `capybara_judge.py` |
| [`fractal/`](./fractal) | ESP32 雙核碎形渲染器 (dual-core fractal demo) | 燒錄韌體、跑 `render.py`，調整韌體頂端的參數做實驗 |

## 0. 環境安裝 (Setup)

先跑工作坊安裝包：下載 bootstrap zip → 解壓縮 → 雙擊 `run.bat`。
它會裝好 Python / PlatformIO / USB 驅動，並把這個 repo clone 到 `C:\dev\codpy-s4-grand\`。
完成後每個作業資料夾 (`pi_cake\`、`fractal\`) 各有一個 `venv\`。

## 啟用 venv（重要：用 cmd，不要用 PowerShell）

PowerShell 的 `Activate.ps1` 常被「**running scripts is disabled on this system**」擋掉。
改用 **cmd** 的 `activate.bat` 就沒這問題，**不用改權限、不用系統管理員**。每個作業資料夾流程都一樣：

1. 在檔案總管裡對作業資料夾（`pi_cake` 或 `fractal`）按 **右鍵 → 在終端機開啟 (Open in Terminal)**
2. 輸入 `cmd` 按 Enter（切換到 cmd）
3. 執行 `venv\Scripts\activate.bat`

提示字元前面出現 `(venv)` 就代表成功，之後的指令都能正常用。

> 💡 Windows 10 沒有「Open in Terminal」？在檔案總管最上面的「網址列」直接打 `cmd` 按 Enter，
> 就會在這個資料夾開一個 cmd 視窗，再從第 3 步開始即可。

## 1. pi_cake（評分機作業）

右鍵 `pi_cake` → Open in Terminal，然後：

```bat
cmd
venv\Scripts\activate.bat
rem 編輯 implementation\pi1\src\pi1.cpp 等的 TODO 區塊
python capybara_judge.py
rem 看錯誤差異： python capybara_judge.py --show-diff
```

細節見 [`pi_cake/README.md`](./pi_cake/README.md)。

## 2. fractal（碎形 demo）

需要 **一塊** ESP32（雙核指的是同一顆晶片的兩個核心）。
右鍵 `fractal` → Open in Terminal，然後（把 `COMx` 換成你的序列埠，安裝完成時會印出來）：

```bat
cmd
venv\Scripts\activate.bat
pio run -t upload --upload-port COMx
python render.py --port COMx
```

想做平行化實驗就改 `fractal/src/main.cpp` 最上方的「可調參數」區（例如 `ASSIGN_MODE`），再重新燒錄。

> 💡 不想啟用 venv？也可以不 activate，直接用 venv 裡的執行檔：
> `venv\Scripts\python.exe capybara_judge.py`、
> `venv\Scripts\pio.exe run -t upload --upload-port COMx`、
> `venv\Scripts\python.exe render.py --port COMx`。

---

## TODO (instructor)
- [ ] 填寫各題的題目敘述、評分標準、繳交方式
- [ ] fractal 的觀察重點 / 實驗題目
- [ ] 確認 bootstrap zip 的下載連結
