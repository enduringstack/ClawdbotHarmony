# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.2

print("Looking for Project Structure dialog...", flush=True)

for w in gw.getAllWindows():
    if 'Project Structure' in w.title:
        print(f"Found at ({w.left}, {w.top}) size {w.width}x{w.height}", flush=True)
        
        # Tab row is at y offset ~57 from window top
        # From screenshot measurements:
        # - Basic Info: ~186 center x
        # - Dependencies: ~277 center x  
        # - Signing Configs: ~382 center x
        # Window left is w.left, so absolute x = w.left + 382
        
        # Adjust for actual window position
        signing_x = w.left + 382
        signing_y = w.top + 57
        
        print(f"Clicking Signing Configs at ({signing_x}, {signing_y})", flush=True)
        pyautogui.click(signing_x, signing_y)
        time.sleep(0.5)
        break
else:
    print("Dialog not found", flush=True)

print("Done", flush=True)
