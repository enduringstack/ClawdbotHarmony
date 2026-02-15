# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.2

print("Looking for Project Structure dialog...", flush=True)

# Find the dialog
for w in gw.getAllWindows():
    if 'Project Structure' in w.title:
        print(f"Found: {w.title} at ({w.left}, {w.top}) size {w.width}x{w.height}", flush=True)
        
        # Click Signing Configs tab (relative to window)
        # Tab row is about 35-40px from top
        # Signing Configs is about 340px from left
        tab_x = w.left + 340
        tab_y = w.top + 38
        
        print(f"Clicking at ({tab_x}, {tab_y})", flush=True)
        pyautogui.click(tab_x, tab_y)
        time.sleep(0.5)
        break
else:
    print("Dialog not found", flush=True)

print("Done", flush=True)
