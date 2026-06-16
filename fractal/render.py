import pygame
import serial
import sys
import time
import struct
import argparse

SERIAL_PORT = 'COM6'      # 預設序列埠 (可用 --port 覆寫，不必改這裡)
BAUD_RATE = 460800        # 鮑率，需與韌體的 SERIAL_BAUD 相同 (可用 --baud 覆寫)
WIDTH, HEIGHT = 800, 600
TOTAL_PIXELS = WIDTH * HEIGHT

def parse_args():
    parser = argparse.ArgumentParser(description="ESP32 雙核碎形渲染器")
    parser.add_argument('-t', '--type', type=int, choices=[0, 1, 2], default=0,
                        help="碎形類型 (0:Mandelbrot, 1:Julia, 2:Burning Ship)")
    parser.add_argument('-i', '--iter', type=int, default=1000,
                        help="最大迭代次數 (預設: 1000)")
    parser.add_argument('-cx', type=float, default=0.0,
                        help="Julia 集合實部常數 (預設: 0.0)")
    parser.add_argument('-cy', type=float, default=0.0,
                        help="Julia 集合虛部常數 (預設: 0.0)")
    parser.add_argument('-p', '--port', type=str, default=SERIAL_PORT,
                        help=f"序列埠 (預設: {SERIAL_PORT})")
    parser.add_argument('-b', '--baud', type=int, default=BAUD_RATE,
                        help=f"鮑率 (預設: {BAUD_RATE})")
    return parser.parse_args()

PALETTE_LENGTH = 14  # 對應你截圖中的 Palette Length

BASE_PALETTE_0 = []
BASE_PALETTE_1 = []

COLOR_TABLE_0 = []
COLOR_TABLE_1 = []

for i in range(PALETTE_LENGTH):
    ratio = i / float(PALETTE_LENGTH - 1) if PALETTE_LENGTH > 1 else 0.0
    
    if ratio < 0.3:
        segment_ratio = ratio / 0.3
        h0 = 60 + int(segment_ratio * 110)
    else:
        segment_ratio = (ratio - 0.7) / 0.7
        h0 = 170 + int(segment_ratio * 90)
        
    c0 = pygame.Color(0, 0, 0)
    c0.hsva = (h0, 40, 100, 100) 
    BASE_PALETTE_0.append(c0)
    if ratio < 0.3:
        segment_ratio = ratio / 0.5
        h1 = 180 + int(segment_ratio * 100)
    else:
        segment_ratio = (ratio - 0.7) / 0.7
        h1 = (280 + int(segment_ratio * 100)) % 360
        
    c1 = pygame.Color(0, 0, 0)
    c1.hsva = (h1, 40, 100, 100) 
    BASE_PALETTE_1.append(c1)

MAX_ITER_COLOR = pygame.Color(20, 20, 35)

for i in range(255):
    palette_index = i % PALETTE_LENGTH
    COLOR_TABLE_0.append(BASE_PALETTE_0[palette_index])
    COLOR_TABLE_1.append(BASE_PALETTE_1[palette_index])

def get_color(iter_count, core_id):
    if iter_count == 255:
        return MAX_ITER_COLOR
    if core_id == 0:
        return COLOR_TABLE_0[iter_count]
    return COLOR_TABLE_1[iter_count]

def send_config(ser, cfg_type, cfg_iter, cfg_cx, cfg_cy):
    ser.reset_input_buffer()
    payload = struct.pack('<BBHff', 0x01, cfg_type, cfg_iter, cfg_cx, cfg_cy)
    ser.write(payload)

def main():
    args = parse_args()
    cfg_type = args.type
    cfg_iter = args.iter
    cfg_cx = args.cx
    cfg_cy = args.cy

    pygame.init()
    correct_packets = 0
    error_packets = 0
    rendered_pixels = 0
    finished = False
    
    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption(f"Fractal Render [Type:{cfg_type} Iter:{cfg_iter}]")
    ser = serial.Serial(args.port, args.baud)
    
    time.sleep(2)
    start_time = time.time()
    send_config(ser, cfg_type, cfg_iter, cfg_cx, cfg_cy)
    
    byte_buffer = b''
    running = True
    last_print_time = time.time()
    last_display_update = time.time()
    
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT: 
                running = False
            elif event.type == pygame.KEYDOWN and finished:
                if event.key == pygame.K_SPACE:
                    screen.fill((0, 0, 0))
                    rendered_pixels = 0
                    correct_packets = 0
                    error_packets = 0
                    finished = False
                    send_config(ser, cfg_type, cfg_iter, cfg_cx, cfg_cy)
                    start_time = time.time()
                    print(f"\n--- 重新啟動渲染 ---")

        if ser.in_waiting > 0:
            byte_buffer += ser.read(ser.in_waiting)
            mv = memoryview(byte_buffer)
            
            offset = 0
            while offset + 4 <= len(mv):
                if mv[offset:offset+4] == b'\x00\x00\x00\xF0':
                    offset += 4
                    continue
                
                packet = int.from_bytes(mv[offset:offset+4], byteorder='little')
                
                if (packet >> 29) == 5:
                    y = (packet >> 19) & 0x3FF
                    x = (packet >> 9) & 0x3FF
                    core_id = (packet >> 8) & 0x01
                    color_val = packet & 0xFF
                    
                    if x < WIDTH and y < HEIGHT:
                        screen.set_at((x, y), get_color(color_val, core_id))
                        rendered_pixels += 1
                    
                    correct_packets += 1
                    offset += 4
                else:
                    error_packets += 1
                    offset += 1 
            
            byte_buffer = byte_buffer[offset:]
            
        current_time = time.time()
        
        if current_time - last_display_update > 0.033:
            pygame.display.flip()
            last_display_update = current_time
        
        if current_time - last_print_time > 5.0 and not finished:
            print(f"進度: {(rendered_pixels/TOTAL_PIXELS*100):.1f}%")
            last_print_time = current_time

        if not finished and rendered_pixels >= TOTAL_PIXELS:
            end_time = time.time()
            print(f"渲染完成！總耗時: {end_time - start_time:.3f} 秒")
            pygame.display.flip()
            finished = True

    ser.close()
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()