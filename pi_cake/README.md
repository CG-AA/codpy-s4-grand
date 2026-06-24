---
title: Capybara PI Guideline

---

# Capybara PI Guideline

## 故事背景
每天下午茶時間，Capybara 最喜歡大吃一條名為「PI」的超長奶油水果蛋糕。這條蛋糕是無限長的，且上面每一段的奶油花紋（數字）都對應著圓周率 $\pi$ 的小數位數。今天水豚君只想優雅地品嚐其中一小段，你的任務是撰寫 C++ 程式並燒錄至 ESP32，精準切下第 $n$ 個花紋到第 $m$ 個花紋的「精華部分」遞給牠。只要成功餵食，水豚君就會開心地頂著橘子泡溫泉！

## 題目說明
輸入包含多行數字 n 與 m，代表你需要輸出 PI 從第 n 位到第 m 位的數字。請注意： 除了小數點以外，每一個數字都代表一個位置（也就是說，第 1 位數字是 3、第 2 位是 1、第 3 位是 4，以此類推）。

### 範例輸入
```!
1 1

2 10

1 100
```

### 範例輸出
```!
3

141592653

3141592653589793238462643383279502884197169399375105820974944592307816406286208998628034825342117067
```
---

## 實作引導說明
本次 PI 的實作，我們會切成三個階段，每個階段都是為了解決同一道問題 (也就是卡皮巴拉吃蛋糕)，但是因應測資範圍還有時限的不同，我們的程式碼也應該要有所調整，所以採取階段式引導的方法，讓同學能逐步了解。

---

## Judge 使用
Capybara Judge System 是一個自動化的 ESP32 評測環境。評測腳本會自動為你完成裝置偵測、編譯燒錄、序列通訊測試與計分。以下是詳細的使用步驟與規則：

#### 環境準備
在開始進行評測之前，請先設定好 Python 的虛擬環境，並安裝所需的相依套件。
首先建立虛擬環境：
```Bash
python -m venv venv
```
啟動虛擬環境：

```Bash
# Windows PowerShell
.\venv\Scripts\Activate.ps1

# Windows CMD
.\venv\Scripts\activate.bat

# Linux / macOS
source venv/bin/activate
```
安裝依賴套件：

```Bash
pip install -r requirements.txt
```
#### 撰寫程式碼與檔案路徑
請依照你正在挑戰的階段，前往對應的路徑修改 TODO 區塊。請注意：只允許修改 TODO 區塊，且不要改動其他無關檔案：

- Level 1 (水豚小寶寶)：請編輯 `implementation/pi1/src/pi1.cpp`

- Level 2 (長大的水豚)：請編輯 `implementation/pi2/src/pi2.cpp`

- Level 3 (進擊的水豚)：請編輯 `implementation/pi3/src/pi3.cpp`

#### 執行評測
將你的 ESP32 透過 USB 連接至電腦，確保虛擬環境已啟動後，直接執行 Judge：

```Bash
python capybara_judge.py
```
Judge 程式會自動偵測 ESP32 的連接埠，接著會自動執行燒錄專案、等待板子就緒、送出測資並比對標準答案。

如果遇到答案錯誤 (Wrong Answer)，你想查看詳細的輸出差異，可以加上 \--show-diff 參數：

```Bash
python capybara_judge.py --show-diff
```
(註：為保持排版整潔，過長的差異文字預設會被截斷，僅顯示前 55 個字元 )

**時限與分數設定** 
系統對各個關卡設有總測試時限：pi1 為 50.0 秒、pi2 與 pi3 各為 150.0 秒。
分數計算會在各 level 內有詳細說明，總分為三個 level 的分數相加，滿分為 100 分。

**評測輸出**
程式執行結束後，畫面上會顯示：
- 各層級的正確率與執行時間
- 加權過後的個階段分數與最終總分
- Capybara 給你的最終稱號與評語

**稱號與評語**
根據總分分數門檻：
- 0
- 0~60
- 60~100
- 100

會分別授予相關的稱號與評價

**下方是 Level 的具體說明與引導**

## Level 1: 水豚小寶寶
**階段題目：** 這階段的卡皮巴拉只是個寶寶，食量不大。代表
$n \le m \le 10000$，也就代表 ESP32 一定能存放得下寶寶想要吃的蛋糕長度 (PI 數值的長度)。

(Hint: 根據題目，我們不需要在意蛋糕怎麼製作的，我們只要把蛋糕存好放在 ESP32 裡就可以了，這段我們已經幫大家放好讀取好了，也就是 pi_data.txt)

**核心知識點:** 
- 0-indexed vs 1-indexed
- 利用 Pointer Address 計算陣列長度
- 邊界防護
- 型別轉換

**計分規則：** 本階段滿分 30 分，計算公式為：$$ \text{Score} = \left( \frac{\text{Pass}}{\text{Total}} \right) \times 30 $$
> $\text{Pass}$ = 通過測資數
> $\text{Total}$ = 總測資數

正常情況下正確輸出即可拿滿 30 分。

**具體作答:** 請修改 ```implementation/pi1/src/pi1.cpp```中的 TODO 區塊：請計算起始與結束的索引，並根據 pi_data_txt 的內容印出對應的 pi 數值。

:::spoiler **implementation/pi1/src/pi1.cpp:**
```cpp!=
// ==========================================
// Do not modify the code outside TODO blocks
// 請勿修改 TODO 區塊以外的程式碼
// ==========================================

#include <Arduino.h>

 // Set up linker symbols to access embedded data
 // 設定 linker 符號以存取嵌入式資料
extern const uint8_t pi_data_txt_start[] asm("_binary_src_pi_data_txt_start");
extern const uint8_t pi_data_txt_end[]   asm("_binary_src_pi_data_txt_end");

void run_pi(const char* tag, const char* payload) {
    int N, M;
    if (sscanf(payload, "%d %d", &N, &M) == 2) {
        Serial.print(tag);
        Serial.print("]");

        // TODO:
        // Calculate the start and ending index, and print the corresponding digits of pi from the data restore in pi_data_txt.
        // 計算起始與結束的索引，並從 pi_data_txt 中印出對應的 pi 位數字。
        
        

        // End of TODO
        
        // Print the ending tag and flush the output
        // 印出結尾標籤並刷新輸出
        Serial.println("[END]");
        Serial.flush();
    }
}
```
:::

---


## Level 2: 長大的水豚
**階段題目:** 這階段的卡皮巴拉長大了，食量特別的大。代表
$n \le m \le 500000$ ，那沒有特別調整容量配置的 ESP32 就放不下蛋糕 (PI 數值的長度) 了，所以我們得使用技巧把蛋糕壓縮的小一點。

(Hint: 根據題目，我們不需要在意蛋糕怎麼製作的，我們只要把蛋糕存好放在 ESP32 裡就可以了，這段我們已經幫大家放好讀取好了，也就是 pi_data.bin，格式是 Packed BCD)

**核心知識點:** 
- 資料處理
- 奇偶數判斷
- 位元運算
- 數字轉字元

**計分規則：** 本階段滿分 30 分，計算公式為：$$ \text{Score} = \left( \frac{\text{Pass}}{\text{Total}} \right) \times 30 $$
> $\text{Pass}$ = 通過測資數
> $\text{Total}$ = 總測資數

正常情況下正確輸出即可拿滿 30 分。

**具體作答:** 請修改 ```implementation/pi2/src/pi2.cpp```中的 TODO 區塊：請計算起始與結束的索引。從壓縮的二進位檔案讀取並解碼 BCD 格式。請善用位元移位 (>> 4) 取得高位元，並使用位元 AND (& 0x0F) 取得低位元。

:::spoiler **implementation/pi2/src/pi2.cpp:**
```cpp!=
// ==========================================
// Do not modify the code outside TODO blocks
// 請勿修改 TODO 區塊以外的程式碼
// ==========================================

#include <Arduino.h>

extern const uint8_t pi_data_bin_start[] asm("_binary_src_pi_data_bin_start");
extern const uint8_t pi_data_bin_end[]   asm("_binary_src_pi_data_bin_end");

void run_pi(const char* tag, const char* payload) {
    int N, M;
    if (sscanf(payload, "%d %d", &N, &M) == 2) {
        Serial.print(tag);
        Serial.print("]");

        // TODO:
        // Calculate the start and ending index.
        // Read from the compressed binary file and decode the BCD format.
        // Hint: Use bitwise shift (>> 4) for high bits and bitwise AND (& 0x0F) for low bits.
        // 計算起始與結束的索引。
        // 從壓縮的二進位檔案讀取並解碼 BCD 格式。
        // 提示：請善用位元移位 (>> 4) 取得高位元，並使用位元 AND (& 0x0F) 取得低位元。
        
        
        
        // End of TODO
        
        Serial.println("[END]");
        Serial.flush();
    }
}
```
:::

---


## Level 3: 進擊的水豚
**階段題目:** 這階段的卡皮巴拉已經進化成暴食水豚了！牠一張口就要吃幾十萬位數的蛋糕。雖然我們在 Level 2 成功用 Packed BCD 壓縮了蛋糕體積，但因為測資高達數十萬筆，如果你還在用 Serial.print() 逐字地遞蛋糕，硬體 UART 的中斷與通訊開銷會讓傳輸變得極度緩慢，直接導致超時。我們得在記憶體裡自己搭一座奶油輸送帶 (Buffer)，把蛋糕切好裝滿一整箱後，用 Serial.write() 一次送出去！

**核心知識點:** 
- 緩衝區儲存
- 批次傳輸
- 緩衝區索引重置

**計分規則：** 本階段滿分 40 分，計算公式為：$$\text{Score} = \left( \frac{\text{Pass}}{\text{Total}} \times 40 \right) \times \min\left(1.0, \frac{11.5}{T - 5.0}\right)$$
> $\text{Pass}$ = 通過測資數
> $\text{Total}$ = 總測資數
> $\text{T}$ = 實際執行時間

本階段在正確輸出之餘，需要成功實作 buffer 才能有足夠的效能來拿滿分。
*提示：若要拿到本關卡的滿分 (40 分)，程式的執行時間大約必須壓在 16.5 秒以內。*

**具體作答請修改 ```implementation/pi3/src/pi3.cpp```中的 TODO 區塊：請將解碼後的 BCD 字元存入緩衝區，滿了再一次用 Serial.write() 批次送出。**

:::spoiler **implementation/pi3/src/pi3.cpp:**
```cpp!=
#include <Arduino.h>

extern const uint8_t pi_data_bin_start[] asm("_binary_src_pi_data_bin_start");
extern const uint8_t pi_data_bin_end[]   asm("_binary_src_pi_data_bin_end");

void run_pi(const char* tag, const char* payload) {
    int N, M;
    if (sscanf(payload, "%d %d", &N, &M) == 2) {
        static char out_buf[2048];
        int buf_idx = 0;

        const char* t = tag;
        while (*t) out_buf[buf_idx++] = *t++;
        out_buf[buf_idx++] = ']';

        // TODO:
        // Testing data is huge. Using Serial.print() for every single digit will cause Time-out.
        // Store the decoded BCD characters into the buffer, and use Serial.write() in batches.
        // 測試資料非常龐大，逐字使用 Serial.print() 會導致 Time-out 逾時。
        // 請將解碼後的 BCD 字元存入緩衝區，滿了再一次用 Serial.write() 批次送出。
        
        

        // End of TODO
        
        const char* end_str = "[END]\r\n";
        while (*end_str) out_buf[buf_idx++] = *end_str++;
        
        if (buf_idx > 0) {
            Serial.write((const uint8_t*)out_buf, buf_idx);
        }
        Serial.flush();
    }
}
```

:::

---

**沒有問題的話可以趕快開始餵食秀啦~**
**祝大家都可以成為傳說中的米其林三星飼養員:D**

---

## 卡皮巴拉的保母級教學

尊貴的飼養員，我是卡皮阿嬤。如果對於餵食還是沒有頭緒，那就跟著這套保母級教學來實作吧！不用害怕，既然我們是要把程式燒錄到 ESP32 控制硬體，只要學會以下幾個簡單的 C++ 魔法指令，你就能順利切出美味的蛋糕了。

---

### C++ 基礎急救包
要完成水豚君的餵食任務，不需要學會整本 C++，只要掌握以下幾個語法就可以了：

#### 1. 怎麼裝東西？(變數與型態)
在程式裡，我們需要箱子來裝數字或文字，宣告方式是 `型態 箱子名稱 = 內容物;`
```cpp
int number = 10;        // 裝整數 (例如：第幾個數字)
char letter = 'A';      // 裝單個字元 (注意：字元要用單引號 ' ' 包起來)
uint8_t byte_val = 255; // 裝一種比較小的整數 (這題會遇到，把它當一般數字看就好)
```

#### 2. 怎麼做數學運算？
電腦可以幫我們做各種數學計算，除了基礎的加減乘除，還有一個寫程式必備的神祕武器「求餘數」：
```cpp
// 基本的加減乘除
int add = 10 + 5;   // 15 (加法)
int sub = 10 - 5;   // 5  (減法)
int mul = 10 * 5;   // 50 (乘法)
int div = 10 / 3;   // 3  (除法：注意！整數除法會「無條件捨去」小數點)

// 神祕武器：求餘數 (%)
int a = 10 % 2;  // a 會是 0，代表 10 是偶數！
int b = 11 % 2;  // b 會是 1，代表 11 是奇數！
```

#### 3. 怎麼做決定？(條件判斷 if-else)
如果你想讓程式「遇到偶數做 A，遇到奇數做 B」，就需要使用 `if-else`：
```cpp
if (條件) {
    // 條件成立的時候做這裡的事情
} else {
    // 條件不成立的時候做這裡的事情
}

// 實際範例：
if (i % 2 == 0) {
    // 如果 i 是偶數，就切蛋糕的左半邊
} else {
    // 否則 (i 是奇數)，就切蛋糕的右半邊
}
```

#### 4. 怎麼重複做事？(迴圈 for)
你要連續切下好幾百個數字，總不能手動複製貼上幾百行程式碼吧？這時候交給 `for` 迴圈：
```cpp
// for(從哪裡開始; 到哪裡結束; 每次做完怎麼改變)
for (int i = 0; i <= 10; i++) {
    // 這裡面的程式碼會被連續執行！
    // i++ 的意思是每次做完，i 就自動加 1
}
```

#### 5. 怎麼拿一排東西裡的特定一個？(陣列 Array)
這點超級重要：**電腦世界是從 0 開始數數的 (0-indexed)**！
假設有一排蛋糕：`int cake[5] = {3, 1, 4, 1, 5};`
* 第一個數字 3，放在 `cake[0]`
* 第二個數字 1，放在 `cake[1]`
所以，如果題目要你拿「第 n 個數字」，你要去拿 `cake[n-1]` 的位子喔！

#### 6. 神奇的字元轉換法
數字的 `3` 和可以印在螢幕上的文字字元 `'3'` 在電腦裡是不一樣的。要怎麼把數字變成字元呢？
**加上 `'0'` 就搞定！**
```cpp
int num = 3;
char digit = '0' + num; // 這樣 digit 就會變成字元 '3' 囉！
```

#### 7. 參考資料
如果上述有不夠清楚的地方，推薦大家到 [W3Schools](https://www.w3schools.com/cpp/) 去找到更詳細的說明。

---

**看完 C++ 的基礎教學後，強烈推薦大家去嘗試寫看看，如果還是遇到問題，下方還有針對各 Level 的急救包歐~**

---


### Level 1 急救包：水豚小寶寶
*卡皮阿嬤的叮嚀：Level 1 的蛋糕沒有壓縮，原本是什麼樣就存在陣列裡。你可以參考以下的程式碼骨架來完成 TODO。*

#### 1. 0-indexed 與邊界防護
人類習慣從第 1 個開始數，但程式陣列是從第 0 個開始裝，所以要把開始與結束的位置減 1。此外，為了防止你一刀切到蛋糕外面導致系統當機，我們要把「結尾位置」減掉「開頭位置」來算出最大長度。

#### 2. 實作骨架參考
請將這段邏輯套用到你的 TODO 區塊中，並補齊印出字元的程式碼：
```cpp
int start_idx = N - 1;
int end_idx = M - 1;

// 計算最大長度，防止切出界
int max_len = pi_data_txt_end - pi_data_txt_start;
if (end_idx >= max_len) {
    end_idx = max_len - 1;
}

// 開始切蛋糕囉！
for (int i = start_idx; i <= end_idx; i++) {
    // 提示：記得把 pi_data_txt_start[i] 強制轉型成 (char) 再印出來喔！
    Serial.print( /* 請填入你要印出的陣列內容 */ );
}
```

---

### Level 2 急救包：長大的水豚
*卡皮阿嬤的叮嚀：Level 2 的蛋糕被「壓縮」了！一個 Byte (位元組) 裡面硬生生塞了兩個數字，你要把它們拆開才能餵食。*

#### 1. 奇偶數與位元運算
因為 1 個 Byte 塞了 2 個數字，所以你要找的第 `i` 個數字，會藏在陣列的第 `i / 2` 個 Byte 裡面。
* **偶數位置**的數字在左邊：請把它往右推 4 格 (`>> 4`)。
* **奇數位置**的數字在右邊：請用遮罩把它蓋住 (`& 0x0F`)。
最後，別忘了用 `+'0'` 把它變成字元！

#### 2. 實作骨架參考
```cpp
int start_idx = N - 1;
int end_idx = M - 1;

for (int i = start_idx; i <= end_idx; i++) {
    // 找出這個數字藏在哪一個 Byte 裡面
    uint8_t byte_val = pi_data_bin_start[i / 2];
    
    if (i % 2 == 0) {
        // 偶數：拿左半邊，並且加上 '0' 轉成字元
        char digit = '0' + (byte_val >> 4);
        Serial.print(digit);
    } else {
        // 奇數：拿右半邊，請善用 & 0x0F 還有加 '0' 的技巧
        char digit = /* 換你試試看組合 '0' + (byte_val & 0x0F) */;
        Serial.print(digit);
    }
}
```

---

### Level 3 急救包：進擊的水豚
*卡皮阿嬤的叮嚀：這隻水豚太會吃了，如果你還像 Level 2 那樣一口一口餵 (`Serial.print`)，ESP32 會直接超時當機。我們要用一個「大箱子(緩衝區)」，裝滿一箱再一口氣倒給牠！*

#### 1. 緩衝區儲存與批次傳輸
程式已經幫你準備好箱子 `out_buf` 和計數器 `buf_idx`。你解碼出字元後，**不要急著印出來**，先把它放進箱子裡。當箱子快滿的時候，再用 `Serial.write` 批次送出。

#### 2. 實作骨架參考
前面的解碼邏輯 (for 迴圈和 if-else 拆解數字) 都跟 Level 2 一樣。假設你已經成功把當下的數字存進 `char digit` 變數了，接下來請這樣做：

```cpp
// 1. 先把字元放進大箱子裡，並且計數器加 1
out_buf[buf_idx] = digit;
buf_idx++; // 或者可以簡寫成 out_buf[buf_idx++] = digit;

// 2. 檢查箱子是不是快滿了 (例如裝了 2000 個)
if (buf_idx >= 2000) {
    // 一口氣把整箱蛋糕推出去
    Serial.write((const uint8_t*)out_buf, buf_idx);
    
    // 3. 最重要的一步：把計數器歸零！箱子才能重新裝
    buf_idx = /* 這裡該填什麼呢？ */;
}
```

*小提醒：當迴圈結束後，如果箱子裡還有剩下的蛋糕 (buf_idx > 0)，程式結尾已經有幫你寫好最後一次的 `Serial.write` 把它清空囉！*
