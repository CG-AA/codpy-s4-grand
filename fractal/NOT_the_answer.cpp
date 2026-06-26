#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include <freertos/queue.h>
#include <freertos/event_groups.h>
#include <esp_task_wdt.h>
#include <math.h>

#define WIDTH 800
#define HEIGHT 600

// ==========================================
// 實驗參數設定區
// ==========================================
// 1: 上下半分派 (Core 0 上, Core 1 下)
// 2: 左右半分派 (Core 0 左, Core 1 右)
// 3: 自己試試看！
// 4: 靜態區塊分派 (透過 Task Queue)
// 5: 區段交錯分派 (依據 CHUNK_SIZE 交錯)
// 6: Mariani-Silver 演算法分派 (結合 Queue 與遞迴分割) 
// 7: 對角線分派 (扭轉負載分布)

#define ASSIGN_MODE 7

// 模式 4 的初始切割數量設定
#define GRID_X 8
#define GRID_Y 6

// 模式 5 的區段大小設定
#define CHUNK_SIZE 16 

// 模式 7 (Mariani-Silver) 遞迴分割的最小寬高閾值
#define MS_BLOCK_SIZE 64
#define MS_THRESHOLD 8
// ==========================================

SemaphoreHandle_t serialMutex;
QueueHandle_t taskQueue;
EventGroupHandle_t renderEventGroup;

const int CORE_0_BIT = (1 << 0);
const int CORE_1_BIT = (1 << 1);

struct BlockTask {
    int start_x, end_x;
    int start_y, end_y;
};

uint8_t current_assign_mode = 7;
uint8_t current_power = 2;
uint8_t fractal_type = 0; 
uint16_t current_max_iter = 1000;
float julia_cx = -0.123f;
float julia_cy = 0.745f;
float current_min_x = -2.0f;
float current_min_y = -1.2f;
float current_max_x = 1.0f;
float current_max_y = 1.2f;

inline int eval_pixel(int x, int y) {
    float x_mapped = current_min_x + (current_max_x - current_min_x) * x / WIDTH;
    float y_mapped = current_min_y + (current_max_y - current_min_y) * y / HEIGHT;
    
    float zr, zi, cr, ci;
    
    if (fractal_type == 0 || fractal_type == 2) { 
        zr = 0; zi = 0;
        cr = x_mapped; ci = y_mapped;
    } else { 
        zr = x_mapped; zi = y_mapped;
        cr = julia_cx; ci = julia_cy;
    }

    int iter = 0;
    while (zr * zr + zi * zi <= 4.0f && iter < current_max_iter) {
        if (fractal_type == 2) {
            zr = fabsf(zr);
            zi = fabsf(zi);
        }
        float acc_r = 1.0f, acc_i = 0.0f;
        for (uint8_t p = 0; p < current_power; p++) {
            float t = acc_r * zr - acc_i * zi;
            acc_i  = acc_r * zi + acc_i * zr;
            acc_r  = t;
        }
        zr = acc_r + cr;
        zi = acc_i + ci;
        iter++;
    }
    return (iter >= current_max_iter) ? 255 : (iter % 255);
}

void render_segment(int y, int start_x, int end_x, int core_id) {
    int len = end_x - start_x;
    if (len <= 0) return;

    uint8_t buffer[8 + len * 2 + 2];
    int idx = 0;

    buffer[idx++] = 0xAA;
    buffer[idx++] = 0xBB;
    buffer[idx++] = (y >> 8) & 0xFF;
    buffer[idx++] = y & 0xFF;
    buffer[idx++] = (start_x >> 8) & 0xFF;
    buffer[idx++] = start_x & 0xFF;
    buffer[idx++] = (len >> 8) & 0xFF;
    buffer[idx++] = len & 0xFF;
    buffer[idx++] = core_id;

    uint8_t current_count = 0;
    uint8_t current_iter = 0;

    for (int x = start_x; x < end_x; x++) {
        uint8_t iter = eval_pixel(x, y);

        if (current_count == 0) {
            current_iter = iter;
            current_count = 1;
        } else if (iter == current_iter && current_count < 255) {
            current_count++;
        } else {
            buffer[idx++] = current_count;
            buffer[idx++] = current_iter;
            current_iter = iter;
            current_count = 1;
        }
    }
    
    if (current_count > 0) {
        buffer[idx++] = current_count;
        buffer[idx++] = current_iter;
    }

    buffer[idx++] = 0x00;
    buffer[idx++] = 0x00;

    if (xSemaphoreTake(serialMutex, portMAX_DELAY) == pdTRUE) {
        Serial.write(buffer, idx);
        xSemaphoreGive(serialMutex);
    }
}

// ==========================================
// Mariani-Silver 演算法相關函數
// ==========================================
void ms_fill_rect(int start_x, int end_x, int start_y, int end_y, int core_id, int color) {
    int len = end_x - start_x;
    if (len <= 0) return;

    for (int y = start_y; y < end_y; y++) {
        // 計算所需的 RLE 區塊數量：每 255 個像素需要 1 組 (2 bytes)
        int max_rle_pairs = (len / 255) + 1;
        
        // 分配記憶體：表頭(8 bytes) + 最大可能 RLE 載荷 + 結尾標記(2 bytes)
        uint8_t buffer[8 + max_rle_pairs * 2 + 2];
        int idx = 0;

        // 1. 寫入 RLE 封包表頭
        buffer[idx++] = 0xAA;
        buffer[idx++] = 0xBB;
        buffer[idx++] = (y >> 8) & 0xFF;
        buffer[idx++] = y & 0xFF;
        buffer[idx++] = (start_x >> 8) & 0xFF;
        buffer[idx++] = start_x & 0xFF;
        buffer[idx++] = (len >> 8) & 0xFF;
        buffer[idx++] = len & 0xFF;
        buffer[idx++] = core_id;

        // 2. 寫入 RLE 載荷 (處理單次計數 > 255 的狀況)
        int remaining = len;
        while (remaining > 0) {
            uint8_t chunk_size = (remaining > 255) ? 255 : remaining;
            buffer[idx++] = chunk_size;
            buffer[idx++] = color; // color 即為迭代次數 (out_iter)
            remaining -= chunk_size;
        }

        // 3. 結尾標記
        buffer[idx++] = 0x00;
        buffer[idx++] = 0x00;

        if (xSemaphoreTake(serialMutex, portMAX_DELAY) == pdTRUE) {
            Serial.write(buffer, idx);
            xSemaphoreGive(serialMutex);
        }
        esp_task_wdt_reset();
        vTaskDelay(pdMS_TO_TICKS(1));
    }
}

void ms_compute_rect(int start_x, int end_x, int start_y, int end_y, int core_id) {
    for (int y = start_y; y < end_y; y++) {
        render_segment(y, start_x, end_x, core_id);
        esp_task_wdt_reset();
        vTaskDelay(pdMS_TO_TICKS(1));
    }
}

void mariani_silver(int start_x, int end_x, int start_y, int end_y, int core_id) {
    int w = end_x - start_x;
    int h = end_y - start_y;
    
    if (w <= MS_THRESHOLD || h <= MS_THRESHOLD) {
        ms_compute_rect(start_x, end_x, start_y, end_y, core_id);
        return;
    }

    int border_color = eval_pixel(start_x, start_y);
    bool uniform = true;

    // 檢查上下邊界
    for (int x = start_x; x < end_x; x++) {
        if (eval_pixel(x, start_y) != border_color || eval_pixel(x, end_y - 1) != border_color) {
            uniform = false;
            break;
        }
    }
    
    // 檢查左右邊界
    if (uniform) {
        for (int y = start_y + 1; y < end_y - 1; y++) {
            if (eval_pixel(start_x, y) != border_color || eval_pixel(end_x - 1, y) != border_color) {
                uniform = false;
                break;
            }
        }
    }

    if (uniform) {
        ms_fill_rect(start_x, end_x, start_y, end_y, core_id, border_color);
    } else {
        int mid_x = start_x + w / 2;
        int mid_y = start_y + h / 2;
        mariani_silver(start_x, mid_x, start_y, mid_y, core_id);
        mariani_silver(mid_x, end_x, start_y, mid_y, core_id);
        mariani_silver(start_x, mid_x, mid_y, end_y, core_id);
        mariani_silver(mid_x, end_x, mid_y, end_y, core_id);
    }
}
// ==========================================

void fractalWorkerTask(void *pvParameters) {
    int core_id = (int)pvParameters;

    if (current_assign_mode == 1) {
        // 1: 上下半分派
        int half_h = HEIGHT / 2;
        int start_y = (core_id == 0) ? 0 : half_h;
        int end_y = (core_id == 0) ? half_h : HEIGHT;
        for (int y = start_y; y < end_y; y++) {
            render_segment(y, 0, WIDTH, core_id);
            esp_task_wdt_reset(); 
            vTaskDelay(pdMS_TO_TICKS(1)); 
        }
    } 
    else if (current_assign_mode == 2) {
        // 2: 左右半分派
        int half_w = WIDTH / 2;
        int start_x = (core_id == 0) ? 0 : half_w;
        int end_x = (core_id == 0) ? half_w : WIDTH;
        for (int y = 0; y < HEIGHT; y++) {
            render_segment(y, start_x, end_x, core_id);
            esp_task_wdt_reset(); 
            vTaskDelay(pdMS_TO_TICKS(1)); 
        }
    }
    else if (current_assign_mode == 3) {
        // 3: 自訂模式
    }
    else if (current_assign_mode == 4) {
        // 4: 靜態區塊分派 (從佇列領取固定區塊並運算)
        BlockTask task;
        while (xQueueReceive(taskQueue, &task, 0) == pdTRUE) {
            ms_compute_rect(task.start_x, task.end_x, task.start_y, task.end_y, core_id);
        }
    }
    else if (current_assign_mode == 5) {
        // 5: 區段交錯分派 (依據 CHUNK_SIZE 交錯)
        for (int y = 0; y < HEIGHT; y++) {
            if (((y / CHUNK_SIZE) % 2) == core_id) {
                render_segment(y, 0, WIDTH, core_id);
                esp_task_wdt_reset(); 
            }
            if (y % CHUNK_SIZE == 0) vTaskDelay(pdMS_TO_TICKS(1)); 
        }
    }
    else if (current_assign_mode == 6) {
        // 6: Mariani-Silver 演算法分派 (從佇列領取初始任務並執行遞迴)
        BlockTask task;
        while (xQueueReceive(taskQueue, &task, 0) == pdTRUE) {
            mariani_silver(task.start_x, task.end_x, task.start_y, task.end_y, core_id);
        }
    }
    else if (current_assign_mode == 7) {
        // 7: 對角線分派 (根據 y 座標等比例切割邊界 x)
        for (int y = 0; y < HEIGHT; y++) {
            int boundary_x = (y * WIDTH) / HEIGHT;  
            if (core_id == 0) {
                if (boundary_x > 0) render_segment(y, 0, boundary_x, core_id);
            } else {
                if (boundary_x < WIDTH) render_segment(y, boundary_x, WIDTH, core_id);
            }
            esp_task_wdt_reset();
            vTaskDelay(pdMS_TO_TICKS(1));
        }
    }

    xEventGroupSetBits(renderEventGroup, (core_id == 0) ? CORE_0_BIT : CORE_1_BIT);
    vTaskDelete(NULL);
}

void fill_task_queue() {
    xQueueReset(taskQueue);
    
    int base_w = WIDTH / GRID_X;
    int rem_w = WIDTH % GRID_X;
    int base_h = HEIGHT / GRID_Y;
    int rem_h = HEIGHT % GRID_Y;

    for (int r = 0; r < GRID_Y; r++) {
        int start_y = r * base_h + (r < rem_h ? r : rem_h);
        int end_y = start_y + base_h + (r < rem_h ? 1 : 0);

        for (int c = 0; c < GRID_X; c++) {
            int start_x = c * base_w + (c < rem_w ? c : rem_w);
            int end_x = start_x + base_w + (c < rem_w ? 1 : 0);

            BlockTask task = { start_x, end_x, start_y, end_y };
            xQueueSend(taskQueue, &task, portMAX_DELAY);
        }
    }
}

void ms_pre_slice(int start_x, int end_x, int start_y, int end_y) {
    int w = end_x - start_x;
    int h = end_y - start_y;
    
    if (w <= MS_BLOCK_SIZE || h <= MS_BLOCK_SIZE) {
        BlockTask task = { start_x, end_x, start_y, end_y };
        xQueueSend(taskQueue, &task, portMAX_DELAY);
        return;
    }

    int border_color = eval_pixel(start_x, start_y);
    bool uniform = true;

    for (int x = start_x; x < end_x; x++) {
        if (eval_pixel(x, start_y) != border_color || eval_pixel(x, end_y - 1) != border_color) {
            uniform = false;
            break;
        }
    }
    
    if (uniform) {
        for (int y = start_y + 1; y < end_y - 1; y++) {
            if (eval_pixel(start_x, y) != border_color || eval_pixel(end_x - 1, y) != border_color) {
                uniform = false;
                break;
            }
        }
    }

    if (uniform) {
        BlockTask task = { start_x, end_x, start_y, end_y };
        xQueueSend(taskQueue, &task, portMAX_DELAY);
    } else {
        int mid_x = start_x + w / 2;
        int mid_y = start_y + h / 2;
        ms_pre_slice(start_x, mid_x, start_y, mid_y);
        ms_pre_slice(mid_x, end_x, start_y, mid_y);
        ms_pre_slice(start_x, mid_x, mid_y, end_y);
        ms_pre_slice(mid_x, end_x, mid_y, end_y);
    }
}

void fill_ms_task_queue() {
    xQueueReset(taskQueue);
    ms_pre_slice(0, WIDTH, 0, HEIGHT);
}

void setup() {
    Serial.setRxBufferSize(16384);
    Serial.begin(460800);
    serialMutex = xSemaphoreCreateMutex();
    taskQueue = xQueueCreate(2500, sizeof(BlockTask));
    renderEventGroup = xEventGroupCreate();
}

void loop() {
    uint8_t buf[30];                          
    while (Serial.available() < 30) {         
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    Serial.readBytes(buf, 30);
    if (buf[0] == 0x01) {
        fractal_type     = buf[1];
        current_max_iter = buf[2] | (buf[3] << 8);
        memcpy(&julia_cx, &buf[4], 4);
        memcpy(&julia_cy, &buf[8], 4);
        current_power    = buf[12];
        if (current_power < 2) current_power = 2;  
        
        memcpy(&current_min_x, &buf[13], 4);
        memcpy(&current_min_y, &buf[17], 4);
        memcpy(&current_max_x, &buf[21], 4);
        memcpy(&current_max_y, &buf[25], 4);
        current_assign_mode = buf[29];
    }

    while(Serial.available()) { Serial.read(); }

    if (current_assign_mode == 4||6) {
        // 產生靜態網格區塊放入佇列
        fill_task_queue();
    }
    
    xEventGroupClearBits(renderEventGroup, CORE_0_BIT | CORE_1_BIT);
    
    xTaskCreatePinnedToCore(fractalWorkerTask, "C0", 8192, (void*)0, 1, NULL, 0);
    xTaskCreatePinnedToCore(fractalWorkerTask, "C1", 8192, (void*)1, 1, NULL, 1);
    
    xEventGroupWaitBits(renderEventGroup, CORE_0_BIT | CORE_1_BIT, pdTRUE, pdTRUE, portMAX_DELAY);
}