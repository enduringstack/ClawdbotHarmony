# -*- coding: utf-8 -*-
"""
Navigate to Signing Configs tab using keyboard
"""
import pyautogui
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(msg, flush=True)

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.2

def main():
    log("Using keyboard to navigate to Signing Configs...")
    
    # Try pressing right arrow to switch tabs
    # First, click on the tab bar area
    log("Clicking near tabs area...")
    pyautogui.click(500, 152)
    time.sleep(0.3)
    
    # Press right arrow twice to get to Signing Configs
    log("Pressing Right arrow to navigate tabs...")
    pyautogui.press('right')
    time.sleep(0.2)
    pyautogui.press('right')
    time.sleep(0.3)
    
    log("Should be on Signing Configs now")
    return 0

if __name__ == "__main__":
    sys.exit(main())
