# -*- coding: utf-8 -*-
"""
Just Run the app using the green Run button
"""
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(msg, flush=True)

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.2

def main():
    log("Finding DevEco window...")
    
    for w in gw.getAllWindows():
        if 'Clawdbot' in w.title or 'ClawdBot' in w.title:
            log(f"Found: {w.title}")
            w.activate()
            time.sleep(0.5)
            break
    
    # Close any dialogs
    log("Closing dialogs...")
    pyautogui.press('escape')
    time.sleep(0.2)
    pyautogui.press('escape')
    time.sleep(0.3)
    
    # Click on the Run button (green triangle in toolbar)
    # Or use menu: Run -> Run 'entry'
    log("Opening Run menu...")
    pyautogui.hotkey('alt', 'r')
    time.sleep(0.5)
    
    # First item should be "Run 'entry'"
    log("Selecting Run 'entry'...")
    pyautogui.press('enter')
    
    log("Run command sent!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
