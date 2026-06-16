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