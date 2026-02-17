# -*- coding: utf-8 -*-
"""
DevEco Studio Sync and Run
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
    log("DevEco Studio Sync and Run")
    log("=" * 50)
    
    win = find_deveco_window()
    if not win:
        log("ERROR: DevEco Studio not found!")
        return 1
    
    log(f"Found: {win.title}")
    win.activate()
    time.sleep(0.5)
    
    # Close any open dialogs/menus
    log("Closing any open dialogs...")
    pyautogui.press('escape')
    time.sleep(0.3)
    pyautogui.press('escape')
    time.sleep(0.3)
    
    # Sync project: File -> Sync and Refresh Project
    log("Syncing project (File -> Sync and Refresh Project)...")
    pyautogui.hotkey('alt', 'f')  # Open File menu
    time.sleep(0.5)
    
    # Navigate to Sync and Refresh Project
    for _ in range(10):
        pyautogui.press('down')
        time.sleep(0.1)
    pyautogui.press('enter')
    time.sleep(3)  # Wait for sync
    
    # Now run: use the Run button or menu
    log("Running app via Run menu...")
    pyautogui.hotkey('alt', 'r')  # Open Run menu
    time.sleep(0.5)
    pyautogui.press('enter')  # Select first item (Run 'entry')
    
    log("Done! Check DevEco Studio for progress.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
