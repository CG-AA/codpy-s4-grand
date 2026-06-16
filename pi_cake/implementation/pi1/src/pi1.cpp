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