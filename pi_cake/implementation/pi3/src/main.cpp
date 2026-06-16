#include <Arduino.h>

extern void run_pi(const char* tag, const char* payload);

String inputBuffer = "";

void setup() {
    setCpuFrequencyMhz(40);
    Serial.begin(460800);
    
    while (!Serial) {
        delay(10);
    }

    Serial.println("[Ready]");
}

void loop() {
    while (Serial.available() > 0) {
        char c = Serial.read();
        
        if (c == '\n') {
            inputBuffer.trim();
            
            if (inputBuffer.length() > 0) {
                int splitIndex = inputBuffer.indexOf(']');
                
                if (splitIndex != -1) {
                    String tag = inputBuffer.substring(0, splitIndex);
                    
                    String payload = inputBuffer.substring(splitIndex + 1);
                    payload.trim();

                    run_pi(tag.c_str(), payload.c_str());
                }
            }
            inputBuffer = ""; 
        } 
        else {
            inputBuffer += c;
        }
    }
}