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

PROJECT_NAMES = ["pi1", "pi2", "pi3", "pi4"]


def is_platformio_project_dir(path):
    """Return True if the path is a valid PlatformIO project root."""
    return (
        isinstance(path, str)
        and os.path.isdir(path)
        and os.path.isfile(os.path.join(path, "platformio.ini"))
    )


def find_platformio_root(start_dir):
    """Find the nearest PlatformIO project root under the given path."""
    if not start_dir or not os.path.isdir(start_dir):
        return None

    start_dir = os.path.abspath(start_dir)

    if is_platformio_project_dir(start_dir):
        return start_dir

    for root, _, files in os.walk(start_dir):
        if "platformio.ini" in files:
            return os.path.abspath(root)

    return None


def find_default_projects():
    """Find valid PlatformIO projects under the implementation directory."""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    src_dir = os.path.join(current_dir, "implementation")

    valid_projects = []

    for name in PROJECT_NAMES:
        candidate_dir = os.path.join(src_dir, name)
        project_root = find_platformio_root(candidate_dir)

        if not project_root:
            continue

        found_cpp = None
        for root, _, files in os.walk(project_root):
            for file_name in files:
                if file_name.endswith(".cpp"):
                    found_cpp = os.path.join(root, file_name)
                    break
            if found_cpp:
                break

        if found_cpp:
            valid_projects.append((project_root, found_cpp))

    return valid_projects


def find_esp32_ports():
    """Scan serial ports for supported ESP32 devices."""
    esp_ports = []
    for port in serial.tools.list_ports.comports():
        if port.vid is not None and port.pid is not None:
            for k_vid, k_pid, chip in ESP32_HW_IDS:
                if port.vid == k_vid and port.pid == k_pid:
                    esp_ports.append({"port": port.device, "chip_type": chip})
                    break
    return esp_ports


def get_esp_mac(port):
    """Read the MAC address of an ESP32 board."""
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
    """Load, repair, and update the persistent device mapping."""
    if os.path.exists(BURN_TABLE_FILE):
        with open(BURN_TABLE_FILE, 'r', encoding='utf-8') as f:
            burn_table = json.load(f)
    else:
        burn_table = {}

    matrix_updated = False
    ready_to_process = []

    available_projects = find_default_projects()
    valid_project_roots = [proj_root for proj_root, _ in available_projects]
    used_roots = set()

    def get_fallback_project():
        for proj_root in valid_project_roots:
            if proj_root not in used_roots:
                return proj_root
        return None

    for mac, cfg in burn_table.items():
        fixed_dir = find_platformio_root(cfg.get("project_dir", ""))
        if fixed_dir:
            cfg["project_dir"] = fixed_dir
            used_roots.add(fixed_dir)
        else:
            fallback = get_fallback_project()
            if fallback:
                cfg["project_dir"] = fallback
                used_roots.add(fallback)
                matrix_updated = True

    proj_idx = 0

    for dev in detected_devices:
        port = dev['port']
        print(f"[*] Probing {port}...")
        mac = get_esp_mac(port)

        if not mac:
            continue

        if mac not in burn_table:
            assigned_dir = None

            while proj_idx < len(available_projects):
                candidate_dir, _ = available_projects[proj_idx]
                proj_idx += 1
                if candidate_dir not in used_roots:
                    assigned_dir = candidate_dir
                    used_roots.add(candidate_dir)
                    break

            if not assigned_dir:
                assigned_dir = get_fallback_project()
                if assigned_dir:
                    used_roots.add(assigned_dir)
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
            cfg = burn_table[mac]
            fixed_dir = find_platformio_root(cfg.get("project_dir", ""))

            if fixed_dir and fixed_dir != cfg.get("project_dir"):
                cfg["project_dir"] = fixed_dir
                used_roots.add(fixed_dir)
                matrix_updated = True
            elif not fixed_dir:
                fallback = get_fallback_project()
                if fallback and cfg.get("project_dir") != fallback:
                    cfg["project_dir"] = fallback
                    used_roots.add(fallback)
                    matrix_updated = True

            if cfg.get("last_seen_port") != port:
                cfg["last_seen_port"] = port
                matrix_updated = True

        ready_to_process.append((port, mac, burn_table[mac]))

    if matrix_updated:
        with open(BURN_TABLE_FILE, 'w', encoding='utf-8') as f:
            json.dump(burn_table, f, indent=4)

    return ready_to_process


def execute_pipeline(port, mac, config):
    """Build and flash the assigned project."""
    proj_dir = config.get("project_dir", "")
    toolchain = config.get("toolchain", "esp-idf")

    fixed_dir = find_platformio_root(proj_dir)
    if fixed_dir:
        proj_dir = fixed_dir
        config["project_dir"] = fixed_dir

    if proj_dir == "0xfee1dead/null" or not is_platformio_project_dir(proj_dir):
        error_msg = f"Invalid PlatformIO project directory [DIR: {proj_dir}] for device [MAC: {mac}]."
        raise FileNotFoundError(error_msg)

    print(f"\n[EXEC] Initializing Toolchain Pipeline...")
    print(f"  -> Target MAC   : {mac}")
    print(f"  -> Target Port  : {port}")
    print(f"  -> Project Dir  : {proj_dir}")
    print(f"  -> Toolchain    : {toolchain}")

    if toolchain == "esp-idf":
        cmd = ["idf.py", "-q", "-p", port, "-b", "460800", "build", "flash"]
    elif toolchain == "platformio":
        cmd = [sys.executable, "-m", "platformio", "run", "-s", "-t", "upload", "--upload-port", port]
    else:
        print(f"[FATAL] Unknown Toolchain type: {toolchain}")
        return

    try:
        print("-" * 40)
        subprocess.run(cmd, cwd=proj_dir, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print("-" * 40)
        print(f"[OK] Build & Flash sequence complete for [MAC: {mac}] (Exit-Zero)!\n")
    except subprocess.CalledProcessError as e:
        print(f"[FAIL] Exception during processing for [MAC: {mac}]. Check syntax or environment variables.\n")
        raise e
    except FileNotFoundError as e:
        print(f"[FATAL] Toolchain executable not found. If using ESP-IDF, ensure 'export.bat/sh' was run.\n")
        raise e

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