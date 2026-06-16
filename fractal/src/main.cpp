#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include <freertos/queue.h>
#include <freertos/event_groups.h>
#include <esp_task_wdt.h>
#include <math.h>

// ===================================================================
//  可調參數 (Tunable knobs) — 改這裡，然後重新燒錄即可實驗
// ===================================================================
#define WIDTH        800      // 影像寬度 (像素)，需與 render.py 相同
#define HEIGHT       600      // 影像高度 (像素)，需與 render.py 相同

// 核心分派策略：兩個核心如何分攤整張畫面的運算
//   1: 上下半分派   (Core 0 上半, Core 1 下半)
//   2: 左右半分派   (Core 0 左半, Core 1 右半)
//   3: 交錯列分派   (Core 0 偶數列, Core 1 奇數列)
//   4: 區塊佇列分派 (動態負載平衡，用 GRID_X/GRID_Y 切塊)
//   5: 區段交錯列   (每 CHUNK_SIZE 列換一次核心)
#define ASSIGN_MODE  2

#define GRID_X       30       // 模式 4：水平切割數 (上限建議 50)
#define GRID_Y       30       // 模式 4：垂直切割數 (上限建議 50)
#define CHUNK_SIZE   16       // 模式 5：區段大小 (每幾列交換一次核心)

#define SERIAL_BAUD  460800   // 序列埠鮑率 (必須與 render.py 的 BAUD_RATE 相同)
#define RX_BUF_SIZE  16384    // 序列埠接收緩衝大小 (位元組)

// 複數平面的視窗範圍 (要顯示的碎形區域；縮放/平移就改這四個值)
const float MIN_R = -2.0f;    // 實部最小值 (畫面左緣)
const float MAX_R =  1.0f;    // 實部最大值 (畫面右緣)
const float MIN_I = -1.2f;    // 虛部最小值 (畫面上緣)
const float MAX_I =  1.2f;    // 虛部最大值 (畫面下緣)
// ===================================================================

SemaphoreHandle_t serialMutex;
QueueHandle_t taskQueue;
EventGroupHandle_t renderEventGroup;

const int CORE_0_BIT = (1 << 0);
const int CORE_1_BIT = (1 << 1);

struct BlockTask {
    int start_x, end_x;
    int start_y, end_y;
};

// 以下四個由 render.py 的設定封包即時覆寫，這裡只是預設值 (非旋鈕)
uint8_t fractal_type = 0;
uint16_t current_max_iter = 1000;
float julia_cx = -0.123f;
float julia_cy = 0.745f;

void render_segment(int y, int start_x, int end_x, int core_id) {
    int len = end_x - start_x;
    if (len <= 0) return;

    uint32_t buffer[WIDTH + 1];
    float y_mapped = MIN_I + (MAX_I - MIN_I) * y / HEIGHT;

    for (int x = start_x; x < end_x; x++) {
        float x_mapped = MIN_R + (MAX_R - MIN_R) * x / WIDTH;
        float zr, zi, cr, ci;

        if (fractal_type == 0) {
            zr = 0; zi = 0;
            cr = x_mapped; ci = y_mapped;
        } else if (fractal_type == 1) {
            zr = x_mapped; zi = y_mapped;
            cr = julia_cx; ci = julia_cy;
        } else {
            zr = 0; zi = 0;
            cr = x_mapped; ci = y_mapped;
        }

        int iter = 0;
        while (zr * zr + zi * zi <= 4.0f && iter < current_max_iter) {
            if (fractal_type == 2) {
                zr = fabs(zr);
                zi = fabs(zi);
            }
            float temp = zr * zr - zi * zi + cr;
            zi = 2.0f * zr * zi + ci;
            zr = temp;
            iter++;
        }

        int out_iter = (iter >= current_max_iter) ? 255 : (iter % 255);
        buffer[x - start_x] = (5U << 29) | (y << 19) | (x << 9) | (core_id << 8) | out_iter;
    }

    buffer[len] = 0xF0000000;

    if (xSemaphoreTake(serialMutex, portMAX_DELAY) == pdTRUE) {
        Serial.write((const uint8_t*)buffer, (len + 1) * 4);
        xSemaphoreGive(serialMutex);
    }
}

void fractalWorkerTask(void *pvParameters) {
    int core_id = (int)pvParameters;

    if (ASSIGN_MODE == 1) {
        int half_h = HEIGHT / 2;
        int start_y = (core_id == 0) ? 0 : half_h;
        int end_y = (core_id == 0) ? half_h : HEIGHT;
        for (int y = start_y; y < end_y; y++) {
            render_segment(y, 0, WIDTH, core_id);
            esp_task_wdt_reset();
            vTaskDelay(pdMS_TO_TICKS(1));
        }
    }
    else if (ASSIGN_MODE == 2) {
        int half_w = WIDTH / 2;
        int start_x = (core_id == 0) ? 0 : half_w;
        int end_x = (core_id == 0) ? half_w : WIDTH;
        for (int y = 0; y < HEIGHT; y++) {
            render_segment(y, start_x, end_x, core_id);
            esp_task_wdt_reset();
            vTaskDelay(pdMS_TO_TICKS(1));
        }
    }
    else if (ASSIGN_MODE == 3) {
        for (int y = core_id; y < HEIGHT; y += 2) {
            render_segment(y, 0, WIDTH, core_id);
            esp_task_wdt_reset();
            vTaskDelay(pdMS_TO_TICKS(1));
        }
    }
    else if (ASSIGN_MODE == 4) {
        BlockTask task;
        while (xQueueReceive(taskQueue, &task, 0) == pdTRUE) {
            for (int y = task.start_y; y < task.end_y; y++) {
                render_segment(y, task.start_x, task.end_x, core_id);
                esp_task_wdt_reset();
            }
            vTaskDelay(pdMS_TO_TICKS(1));
        }
    }
    else if (ASSIGN_MODE == 5) {
        for (int y = 0; y < HEIGHT; y++) {
            // 根據 y 座標所在的區段，判定該由哪個核心執行
            if (((y / CHUNK_SIZE) % 2) == core_id) {
                render_segment(y, 0, WIDTH, core_id);
                esp_task_wdt_reset();
            }
            if (y % CHUNK_SIZE == 0) vTaskDelay(pdMS_TO_TICKS(1));
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
        // 使用整數模除補償演算法分配不平整的邊界
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

void setup() {
    Serial.setRxBufferSize(RX_BUF_SIZE);
    Serial.begin(SERIAL_BAUD);
    serialMutex = xSemaphoreCreateMutex();
    // 預分配最大 2500 個佇列長度，滿足 50x50 的區塊上限
    taskQueue = xQueueCreate(2500, sizeof(BlockTask));
    renderEventGroup = xEventGroupCreate();
}

void loop() {
    uint8_t buf[12];
    while (Serial.available() < 12) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }

    Serial.readBytes(buf, 12);
    if (buf[0] == 0x01) {
        fractal_type = buf[1];
        current_max_iter = buf[2] | (buf[3] << 8);
        memcpy(&julia_cx, &buf[4], 4);
        memcpy(&julia_cy, &buf[8], 4);
    }

    while(Serial.available()) { Serial.read(); }

    if (ASSIGN_MODE == 4) {
        fill_task_queue();
    }

    xEventGroupClearBits(renderEventGroup, CORE_0_BIT | CORE_1_BIT);

    xTaskCreatePinnedToCore(fractalWorkerTask, "C0", 8192, (void*)0, 1, NULL, 0);
    xTaskCreatePinnedToCore(fractalWorkerTask, "C1", 8192, (void*)1, 1, NULL, 1);

    xEventGroupWaitBits(renderEventGroup, CORE_0_BIT | CORE_1_BIT, pdTRUE, pdTRUE, portMAX_DELAY);
}
