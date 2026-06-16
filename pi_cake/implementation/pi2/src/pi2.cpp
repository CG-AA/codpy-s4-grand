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