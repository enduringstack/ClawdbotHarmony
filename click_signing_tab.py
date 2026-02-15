# -*- coding: utf-8 -*-
"""
Click on Signing Configs tab
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
    log("Clicking on Signing Configs tab...")
    # The tab should be around x=634 based on the screenshot layout
    # Let me click on "Signing Configs" tab
    # Based on screenshot: Basic Info | Dependencies | Signing Configs
    # Approximate position for Signing Configs tab
    pyautogui.click(634, 152)  # Adjust if needed
    time.sleep(0.5)
    log("Clicked!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
