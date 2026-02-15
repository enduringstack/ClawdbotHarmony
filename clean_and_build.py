# -*- coding: utf-8 -*-
"""
DevEco Studio Clean and Build
"""
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(msg, flush=True)

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.3

def find_deveco_window():
    for w in gw.getAllWindows():
        if 'Clawdbot' in w.title or 'ClawdBot' in w.title or 'DevEco' in w.title:
            return w
    return None

def main():
    log("=" * 50)
    log("DevEco Studio Clean and Build")
    log("=" * 50)
    
    win = find_deveco_window()
    if not win:
        log("ERROR: DevEco Studio not found!")
        return 1
    
    log(f"Found: {win.title}")
    win.activate()
    time.sleep(0.5)
    
    # Close any open dialogs/menus
    log("Closing any dialogs...")
    pyautogui.press('escape')
    time.sleep(0.2)
    pyautogui.press('escape')
    time.sleep(0.3)
    
    # Clean project: Build -> Clean Project
    log("Cleaning project (Build -> Clean Project)...")
    pyautogui.hotkey('alt', 'b')  # Open Build menu
    time.sleep(0.5)
    
    # Navigate to Clean Project (usually near the bottom)
    for _ in range(8):
        pyautogui.press('down')
        time.sleep(0.1)
    pyautogui.press('enter')
    time.sleep(5)  # Wait for clean
    
    # Now rebuild: Build -> Rebuild Project
    log("Rebuilding project (Build -> Rebuild Project)...")
    pyautogui.hotkey('alt', 'b')
    time.sleep(0.5)
    
    # Navigate to Rebuild Project
    for _ in range(7):
        pyautogui.press('down')
        time.sleep(0.1)
    pyautogui.press('enter')
    
    log("Rebuild started. This may take a few minutes...")
    return 0

if __name__ == "__main__":
    sys.exit(main())
