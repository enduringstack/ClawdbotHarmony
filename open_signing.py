# -*- coding: utf-8 -*-
"""
Open signing configs dialog
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
    
    # Close search dialog if open
    pyautogui.press('escape')
    time.sleep(0.2)
    
    # Open File -> Project Structure
    log("Opening File -> Project Structure...")
    pyautogui.hotkey('alt', 'f')
    time.sleep(0.5)
    
    # Navigate to Project Structure (usually with Ctrl+Alt+Shift+S)
    pyautogui.press('escape')
    time.sleep(0.2)
    pyautogui.hotkey('ctrl', 'alt', 'shift', 's')
    
    log("Project Structure dialog should be open now.")
    log("Please configure signing manually.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
