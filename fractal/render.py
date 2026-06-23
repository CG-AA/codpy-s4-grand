import pygame
import serial
import sys
import time
import struct
import argparse

SERIAL_PORT = 'COM6'
BAUD_RATE = 460800
WIDTH, HEIGHT = 800, 600
TOTAL_PIXELS = WIDTH * HEIGHT

def parse_args():
    parser = argparse.ArgumentParser(description="ESP32 雙核碎形渲染器 (RLE 壓縮版)")
    parser.add_argument('-t', '--type', type=int, choices=[0, 1, 2], default=0,
                        help="碎形類型 (0:Mandelbrot, 1:Julia, 2:Burning Ship)")
    parser.add_argument('-i', '--iter', type=int, default=1000,
                        help="最大迭代次數 (預設: 1000)")
    parser.add_argument('-cx', type=float, default=-0.123,
                        help="Julia 集合實部常數 (預設: -0.123)")
    parser.add_argument('-cy', type=float, default=0.745,
                        help="Julia 集合虛部常數 (預設: 0.745)")
    parser.add_argument('-n', '--power', type=int, default=2,
                        help="碎形 z^n 的次方數 (預設: 2 建議範圍: 2~8)")
    parser.add_argument('-r', '--rect', type=float, nargs=4, default=None,
                        help="視窗範圍: min_x min_y max_x max_y (例如: -2.0 -1.2 1.0 1.2)")
    parser.add_argument('-m', '--mode', type=int, choices=range(1, 8), default=7,
                        help="任務切割模式 (1~7，預設: 7)")
    return parser.parse_args()

PALETTE_LENGTH = 14

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

def enforce_aspect_ratio(min_x, min_y, max_x, max_y, target_ratio):
    w = max_x - min_x
    h = max_y - min_y
    cx = min_x + w / 2.0
    cy = min_y + h / 2.0
    
    current_ratio = w / h
    
    if current_ratio < target_ratio:
        w = h * target_ratio
    elif current_ratio > target_ratio:
        h = w / target_ratio
        
    return cx - w / 2.0, cy - h / 2.0, cx + w / 2.0, cy + h / 2.0

def send_config(ser, cfg_type, cfg_iter, cfg_cx, cfg_cy, cfg_power, min_x, min_y, max_x, max_y, mode):
    ser.reset_input_buffer()
    payload = struct.pack('<BBHffBffffB',
                          0x01, cfg_type, cfg_iter,
                          cfg_cx, cfg_cy, cfg_power,
                          min_x, min_y, max_x, max_y, mode)
    ser.write(payload)

def main():
    args = parse_args()
    cfg_type = args.type
    cfg_iter = args.iter
    cfg_cx = args.cx
    cfg_cy = args.cy
    cfg_power = args.power
    cfg_mode = args.mode

    if args.rect is None:
        if cfg_type == 1:
            cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y = -1.5, -1.5, 1.5, 1.5
        else:
            cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y = -2.0, -1.2, 1.0, 1.2
    else:
        cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y = args.rect

    target_ratio = WIDTH / float(HEIGHT)
    cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y = enforce_aspect_ratio(
        cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y, target_ratio
    )
    
    pygame.init()
    rendered_pixels = 0
    finished = False
    
    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption(f"Fractal [Type:{cfg_type} Iter:{cfg_iter} z^{cfg_power} Mode:{cfg_mode}]")
    ser = serial.Serial(SERIAL_PORT, BAUD_RATE)
    
    time.sleep(2)
    start_time = time.time()
    send_config(ser, cfg_type, cfg_iter, cfg_cx, cfg_cy, cfg_power, cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y, cfg_mode)
    
    byte_buffer = bytearray()
    running = True
    last_print_time = time.time()
    last_display_update = time.time()
    
    state = 0
    header_buf = bytearray()
    current_y = 0
    current_x = 0
    current_len = 0
    current_core_id = 0
    
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT: 
                running = False
            elif event.type == pygame.KEYDOWN and finished:
                if event.key == pygame.K_SPACE:
                    screen.fill((0, 0, 0))
                    rendered_pixels = 0
                    finished = False
                    byte_buffer.clear()
                    state = 0
                    send_config(ser, cfg_type, cfg_iter, cfg_cx, cfg_cy, cfg_power, cfg_min_x, cfg_min_y, cfg_max_x, cfg_max_y, cfg_mode)
                    start_time = time.time()
                    print(f"\n--- 重新啟動渲染 ---")

        if ser.in_waiting > 0:
            byte_buffer.extend(ser.read(ser.in_waiting))
            
        offset = 0
        while offset < len(byte_buffer):
            if state == 0:
                if byte_buffer[offset] == 0xAA:
                    state = 1
                offset += 1
            elif state == 1:
                if byte_buffer[offset] == 0xBB:
                    state = 2
                    header_buf.clear()
                elif byte_buffer[offset] == 0xAA:
                    pass 
                else:
                    state = 0
                offset += 1
            elif state == 2:
                needed = 7 - len(header_buf)
                avail = len(byte_buffer) - offset
                take = min(needed, avail)
                header_buf.extend(byte_buffer[offset:offset+take])
                offset += take
                if len(header_buf) == 7:
                    current_y = (header_buf[0] << 8) | header_buf[1]
                    current_x = (header_buf[2] << 8) | header_buf[3]
                    current_len = (header_buf[4] << 8) | header_buf[5]
                    current_core_id = header_buf[6]
                    state = 3
            elif state == 3:
                segment_finished = False
                while offset + 1 < len(byte_buffer):
                    count = byte_buffer[offset]
                    val = byte_buffer[offset+1]
                    
                    if count == 0 and val == 0:
                        state = 0
                        offset += 2
                        segment_finished = True
                        break
                    
                    color = get_color(val, current_core_id)
                    
                    if current_y < HEIGHT:
                        end_x = min(current_x + count, WIDTH)
                        if end_x > current_x:
                            pygame.draw.line(screen, color, (current_x, current_y), (end_x - 1, current_y))
                            rendered_pixels += (end_x - current_x)
                    
                    current_x += count
                    offset += 2
                    
                if not segment_finished:
                    break
        
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
            print(f"算繪完成！總耗時: {end_time - start_time:.3f} 秒")
            pygame.display.flip()
            finished = True

    ser.close()
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()