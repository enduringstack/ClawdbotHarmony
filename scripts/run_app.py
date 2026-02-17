# -*- coding: utf-8 -*-
"""
DevEco Studio Run App - Build and deploy in one step
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

def run_app():
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
    
    # Use Shift+F10 to Run (or Ctrl+R in some versions)
    log("Triggering Run (Shift+F10)...")
    pyautogui.hotkey('shift', 'F10')
    
    log("Run command sent! App will build and deploy automatically.")
    log("Check DevEco Studio for build progress.")
    return True

def main():
    log("=" * 50)
    log("DevEco Studio Run App")
    log("=" * 50)
    
    if not run_app():
        return 1
    
    log("\nDone! Watch DevEco Studio for build and deployment status.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
