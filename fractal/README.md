
# **實驗實作：ESP32 雙核碎形渲染器環境建置**

本指南將帶領你配置一個高效能的碎形算繪系統，利用 ESP32 的雙核心並行運算能力，並透過 Python 進行即時視覺化呈現。

## **一、 環境初始化步驟**

請嚴格按照以下順序操作，確保路徑與配置完全一致：
 
1. **依賴安裝**：
   假如還沒安裝環境配置，在終端機執行以下指令安裝必要的 Python 庫：
    ```bash
    pip install -r requirements.txt && pip install pygame
    ```  
5. **硬體識別與初始化**：  
   * 進入 fractal 目錄。
   * 執行 `python BurnerHub.py` 一次以生成 `burn_matrix.json`。  
   * **重要**：請至輸出確認 ESP32 開發板的 **COM Port** 編號。  
6. **修改燒錄設定**：
   編輯 `burn_matrix.json`，將 project\_dir 的路徑設定為指向你的實作目錄，例如：...`CODPY-S4-GRAND\fractal\ESP32-FRAC-1`。  
7. **配置通訊埠**：
   打開 `render.py`，將第 8 行的 SERIAL\_PORT 修改為你在步驟 5 紀錄的 COM Port。  
8. **燒錄與啟動**：  
   * 再次執行 `python BurnerHub.py` 進行韌體燒錄。  
   * 最後執行 `python render.py` 啟動渲染監控介面。

## **二、 程式內容教程與解析**

### **1\. 如何使用 render.py？**

`render.py` 不僅是顯示器，它還能透過命令行參數控制 ESP32 的運算行為。

#### 核心參數說明
| 參數 | 說明 | 預設值 |
| :--- | :--- | :--- |
| `-t, --type` | 碎形類型 (0: Mandelbrot, 1: Julia, 2: Burning Ship) | 0 |
| `-i, --iter` | 最大迭代次數，越高畫質越細膩但運算越慢 | 5000 |
| `-cx, -cy` | 當類型為 Julia 時的複數常數 $c$ | -0.123, 0.745 |
| `-n, --power` | 碎形公式的次方數 $z^n$ (建議範圍 2~8) | 2 |
| `-m, --mode` | 任務切割分配模式 (1~3) | 1 |
| `-r, --rect` | 指定視窗範圍 `min_x min_y max_x max_y` | 自動計算 |

#### 範例：渲染 Julia 集合

如果你想觀察特殊的 Julia 集合圖形，可以輸入：
```bash
python render.py -t 1 -cx -0.8 -cy 0.156 -i 500
```

### **2\. 修改 main.cpp 中的 TODO 位置**

在 main.cpp 中，fractalWorkerTask 是處理並行運算的關鍵。

**挑戰任務**：請找到 ASSIGN\_MODE \== 3 的 TODO 位置。

**實作引導：**

你需要在此處定義 Core 0 與 Core 1 如何分配工作。一個簡單且高效的嘗試是「奇偶行分派」：

* 讓 core\_id \== 0 的核心處理偶數行 (y % 2 \== 0)。  
* 讓 core\_id \== 1 的核心處理奇數行 (y % 2 \== 1)。

```cpp
else if (ASSIGN_MODE == 3) {
    // 範例：奇偶行簡單分派邏輯
    for (int y = core_id; y < HEIGHT; y += 2) {
        render_segment(y, 0, WIDTH, core_id); 
        esp_task_wdt_reset(); // 餵狗防止重新開機
        vTaskDelay(pdMS_TO_TICKS(1)); // 釋放 CPU 權限
    }  
}
```

### **3\. 理解 RLE (行程長度編碼) 壓縮**

為了讓序列傳輸跟上雙核計算的速度，我們在 render\_segment 中使用了 RLE 壓縮：

* ESP32 不會逐點傳送顏色，而是傳送「顏色值」與「連續出現的次數」。  
* 例如：連續 50 個點都是黑色，ESP32 只會傳送 \[50, 0\]，大幅節省傳輸頻寬。

## **三、 常見問題與關鍵提醒**

* **序列埠速率**：本實作使用 460800 高速傳輸，請確保你的 USB 傳輸線品質優良，避免數據遺失導致畫面產生雜訊。  
* **看門狗 (WDT)**：在長時間運算的 for 迴圈中，必須包含 esp\_task\_wdt\_reset()，否則 ESP32 會認為程式當機而強制重啟。  
* **浮點運算優化**：在 eval\_pixel 中，我們使用 float 進行複數運算以利用 ESP32 的硬體浮點運算單元 (FPU)。

## **四、任務**
> 這裡有三個碎形模板，請幫幫卡皮巴拉想想該怎麼調整分配模式才能達到最快的算繪效率吧！

#### 任務一
```bash
python .\render.py -t 2 -i 5000 -r -2.0 -1.2 1.0 1.2 -m # -m 後面是分配模式的參數，例：-m 1
# 這會畫出一個燃燒船碎形，觀察看看怎麼分割和加速吧！
```
#### 任務二
```bash
python .\render.py -t 1 -i 2000 -cx -0.123 -cy 0.745 -n 3 -r -1 -0.8 1 1.2 -m # -m 後面是分配模式的參數，例：-m 1
# 這會畫出一個如同三角形的碎形，黑色區域的面積怎麼分割成一樣的比例呢？
```
#### 任務三
```bash
python .\render.py -t 0 -i 10000 -r -0.745417 0.117996 -0.744717 0.118696 -m # -m 後面是分配模式的參數，例：-m 1
# 曼德博集合的一個小島
```
#### 任務四
```bash
python .\render.py -t 1 -i 15000 -cx -0.74546 -cy 0.11669 -r -0.575 -0.1 -0.3 0.15 -m # -m 後面是分配模式的參數，例：-m 1
# 看起來像一張蜘蛛網！
```


