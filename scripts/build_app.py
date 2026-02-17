# -*- coding: utf-8 -*-
"""
DevEco Studio Build Automation
"""
import pyautogui
import pygetwindow as gw
import time
import subprocess
import os
import sys

# Unbuffered output
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(msg, flush=True)

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.3

HAP_PATH = r"C:\Users\Liuho\ClawdBotHarmony\entry\build\default\outputs\default\entry-default-signed.hap"
HDC_PATH = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"

def find_deveco_window():
    for w in gw.getAllWindows():
        if 'Clawdbot' in w.title or 'ClawdBot' in w.title or 'DevEco' in w.title:
            return w
    return None

def trigger_build():
    win = find_deveco_window()
    if not win:
        log("ERROR: DevEco Studio window not found!")
        return False
    
    log(f"Found window: {win.title}")
    log("Activating window...")
    win.activate()
    time.sleep(1)
    
    win.maximize()
    time.sleep(0.5)
    
    log("Triggering build via menu (Alt+B)...")
    pyautogui.hotkey('alt', 'b')
    time.sleep(0.8)
    
    log("Navigating menu to Build Hap(s)...")
    # Navigate down to Build Hap(s)/APP(s)
    for i in range(3):
        pyautogui.press('down')
        time.sleep(0.15)
    
    # Open submenu
    pyautogui.press('right')
    time.sleep(0.3)
    
    # Select Build Hap(s)
    pyautogui.press('enter')
    
    log("Build command sent!")
    return True

def wait_for_hap(timeout=180):
    log(f"\nWaiting for build to complete (timeout: {timeout}s)...")
    
    initial_mtime = 0
    if os.path.exists(HAP_PATH):
        initial_mtime = os.path.getmtime(HAP_PATH)
        log(f"Existing HAP mtime: {time.ctime(initial_mtime)}")
    else:
        log("No existing HAP file")
    
    start = time.time()
    while time.time() - start < timeout:
        time.sleep(5)
        elapsed = int(time.time() - start)
        
        if os.path.exists(HAP_PATH):
            current_mtime = os.path.getmtime(HAP_PATH)
            if current_mtime > initial_mtime + 5:
                log(f"\nHAP file updated at {time.ctime(current_mtime)}")
                return True
        
        log(f"  Waiting... {elapsed}s")
    
    log(f"\nBuild timeout after {timeout}s")
    return False

def install_to_device():
    if not os.path.exists(HAP_PATH):
        log(f"ERROR: HAP not found: {HAP_PATH}")
        return False
    
    log(f"\nInstalling to device...")
    result = subprocess.run([HDC_PATH, "install", HAP_PATH], capture_output=True, text=True)
    log(result.stdout)
    if result.stderr:
        log(result.stderr)
    
    return result.returncode == 0

def main():
    log("=" * 50)
    log("DevEco Studio Build & Install")
    log("=" * 50)
    
    if not trigger_build():
        return 1
    
    if not wait_for_hap():
        return 1
    
    if not install_to_device():
        return 1
    
    log("\n" + "=" * 50)
    log("SUCCESS: App built and installed!")
    log("=" * 50)
    return 0

if __name__ == "__main__":
    sys.exit(main())
