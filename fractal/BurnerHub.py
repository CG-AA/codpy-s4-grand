import serial.tools.list_ports
import subprocess
import json
import os
import re
import time
import sys

BURN_TABLE_FILE = "burn_matrix.json"

ESP32_HW_IDS = [
    (0x10C4, 0xEA60, "Silicon Labs CP210x"),
    (0x1A86, 0x7523, "WCH CH340"),
    (0x303A, 0x1001, "Espressif Native USB"),
    (0x0403, 0x6001, "FTDI FT232RL"),
]

def find_default_projects():
    """
    Search upward for the "Section4-ESP32" directory (up to 5 levels deep),
    then look for main.cpp within the src/ESP32-1 and src/ESP32-2 subdirectories.
    Returns a list of tuples containing (absolute path to project root, absolute path to main.cpp).
    """
    current_dir = os.path.abspath(os.getcwd())
    base_dir = None
    
    for _ in range(6):
        target = os.path.join(current_dir, "Section4-ESP32")
        if os.path.isdir(target):
            base_dir = target
            break
        
        parent_dir = os.path.dirname(current_dir)
        if parent_dir == current_dir:
            break
        current_dir = parent_dir
        
    valid_projects = []
    
    if base_dir:
        src_dir = os.path.join(base_dir, "src")
        for proj_name in ["ESP32-1", "ESP32-2"]:
            proj_root = os.path.join(src_dir, proj_name)
            
            main_cpp_1 = os.path.join(proj_root, "main.cpp")
            main_cpp_2 = os.path.join(proj_root, "src", "main.cpp")
            
            if os.path.isfile(main_cpp_1):
                valid_projects.append((proj_root, main_cpp_1))
            elif os.path.isfile(main_cpp_2):
                valid_projects.append((proj_root, main_cpp_2))
                
    return valid_projects

def find_esp32_ports():
    """Scan system COM Ports for matching hardware IDs"""
    esp_ports = []
    for port in serial.tools.list_ports.comports():
        if port.vid is not None and port.pid is not None:
            for k_vid, k_pid, chip in ESP32_HW_IDS:
                if port.vid == k_vid and port.pid == k_pid:
                    esp_ports.append({"port": port.device, "chip_type": chip})
                    break
    return esp_ports

def get_esp_mac(port):
    """Extract hardware MAC Address using esptool"""
    try:
        result = subprocess.run(
            [sys.executable, "-m", "esptool", "--port", port, "read_mac"],
            capture_output=True, text=True, timeout=5
        )
        match = re.search(r"MAC:\s+([0-9a-fA-F:]+)", result.stdout)
        if match:
            return match.group(1)
    except Exception as e:
        print(f"[ERROR] Failed to probe {port}: {e}")
    return None

def manage_state_matrix(detected_devices):
    """Maintain the Persistent State Matrix (JSON configuration)"""
    if os.path.exists(BURN_TABLE_FILE):
        with open(BURN_TABLE_FILE, 'r', encoding='utf-8') as f:
            burn_table = json.load(f)
    else:
        burn_table = {}

    matrix_updated = False
    ready_to_process = []
    
    available_projects = find_default_projects()
    proj_idx = 0

    for dev in detected_devices:
        port = dev['port']
        print(f"[*] Probing {port}...")
        mac = get_esp_mac(port)
        
        if not mac: continue

        if mac not in burn_table:
            if proj_idx < len(available_projects):
                proj_root, main_cpp_path = available_projects[proj_idx]
                assigned_dir = proj_root
                print(f"[+] Discovered main.cpp at: {main_cpp_path}")
                proj_idx += 1
            else:
                assigned_dir = "0xfee1dead/null"

            burn_table[mac] = {
                "project_dir": assigned_dir, 
                "toolchain": "platformio",
                "last_seen_port": port
            }
            matrix_updated = True
            print(f"[+] New device registered [MAC: {mac}]. Project assigned: {assigned_dir}")
        else:
            if burn_table[mac]["last_seen_port"] != port:
                burn_table[mac]["last_seen_port"] = port
                matrix_updated = True
            
        ready_to_process.append((port, mac, burn_table[mac]))

    if matrix_updated:
        with open(BURN_TABLE_FILE, 'w', encoding='utf-8') as f:
            json.dump(burn_table, f, indent=4)
            
    return ready_to_process

def execute_pipeline(port, mac, config):
    """Execute the Build & Flash pipeline"""
    proj_dir = config.get("project_dir", "")
    toolchain = config.get("toolchain", "esp-idf")

    if proj_dir == "0xfee1dead/null" or not os.path.isdir(proj_dir):
        print(f"[WARN] Invalid project directory [DIR: {proj_dir}] for device [MAC: {mac}]. Skipping.")
        return

    print(f"\n[EXEC] Initializing Toolchain Pipeline...")
    print(f"  -> Target MAC   : {mac}")
    print(f"  -> Target Port  : {port}")
    print(f"  -> Project Dir  : {proj_dir}")
    print(f"  -> Toolchain    : {toolchain}")

    if toolchain == "esp-idf":
        cmd = ["idf.py", "-p", port, "-b", "460800", "build", "flash"]
    elif toolchain == "platformio":
        cmd = [sys.executable, "-m", "platformio", "run", "-t", "upload", "--upload-port", port]
    else:
        print(f"[FATAL] Unknown Toolchain type: {toolchain}")
        return

    try:
        print("-" * 40)
        subprocess.run(cmd, cwd=proj_dir, check=True)
        print("-" * 40)
        print(f"[OK] Build & Flash sequence complete for [MAC: {mac}] (Exit-Zero)!\n")
    except subprocess.CalledProcessError:
        print(f"[FAIL] Exception during processing for [MAC: {mac}]. Check syntax or environment variables.\n")
    except FileNotFoundError:
        print(f"[FATAL] Toolchain executable not found. If using ESP-IDF, ensure 'export.bat/sh' was run.\n")

if __name__ == "__main__":
    print("=== ESP32 Orchestrator (Build & Provision) ===")
    devices = find_esp32_ports()
    
    if not devices:
        print("No ESP32 devices detected.")
    else:
        print(f"Detected {len(devices)} physical COM Ports. Reading MAC addresses...")
        task_queue = manage_state_matrix(devices)
        
        for port, mac, config in task_queue:
            execute_pipeline(port, mac, config)
            time.sleep(1)