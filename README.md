# Codpy S4 — ESP32 作業包 (Assignment Pack)

> ⚠️ Placeholder — full assignment write-up TBD.

兩個 ESP32 作業，一個 repo。Two ESP32 assignments in one repo.

| 資料夾 | 是什麼 | 你要做什麼 |
|---|---|---|
| [`pi_cake/`](./pi_cake) | 卡皮巴拉評分機 — π 數字題 (capybara judge) | 填 `implementation/pi{1,2,3}/src/pi*.cpp` 的 TODO，跑 `capybara_judge.py` |
| [`fractal/`](./fractal) | ESP32 雙核碎形渲染器 (dual-core fractal demo) | 燒錄韌體、跑 `render.py`，調整韌體頂端的參數做實驗 |

## 0. 環境安裝 (Setup)

先跑工作坊安裝包 (download the bootstrap zip, extract, double-click `run.bat`)。
它會裝好 Python / PlatformIO / USB 驅動，並把這個 repo clone 到 `C:\dev\`。
完成後每個作業資料夾各有一個 `venv\`。

## 1. pi_cake (評分機作業)

```powershell
cd pi_cake
.\venv\Scripts\Activate.ps1
# 編輯 implementation\pi1\src\pi1.cpp 等的 TODO 區塊
python capybara_judge.py            # 加 --show-diff 看錯誤差異
```
細節見 [`pi_cake/README.md`](./pi_cake/README.md)。

## 2. fractal (碎形 demo)

需要 **一塊** ESP32 (雙核指的是同一顆晶片的兩個核心)。

```powershell
cd fractal
.\venv\Scripts\Activate.ps1
pio run -t upload --upload-port <COMx>   # 燒錄韌體
python render.py --port <COMx>           # 開啟渲染視窗
```
想做平行化實驗就改 `fractal/src/main.cpp` 最上方的「可調參數」區 (例如 `ASSIGN_MODE`)，再重新燒錄。

---

## TODO (instructor)
- [ ] 填寫各題的題目敘述、評分標準、繳交方式
- [ ] fractal 的觀察重點 / 實驗題目
- [ ] 確認 bootstrap zip 的下載連結
