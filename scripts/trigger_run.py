# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.3

print("Finding DevEco window...", flush=True)

for w in gw.getAllWindows():
    if 'ClawdbotHarm' in w.title or 'DevEco' in w.title:
        print(f"Found: {w.title}", flush=True)
        
        # Click on the window to focus it
        pyautogui.click(w.left + 100, w.top + 100)
        time.sleep(0.3)
        
        # Press Shift+F10 to Run
        print("Pressing Shift+F10 to Run...", flush=True)
        pyautogui.hotkey('shift', 'F10')
        time.sleep(1)
        
        # Or use toolbar Run button (green triangle)
        # Usually at around x=720 in the toolbar
        break

print("Run triggered!", flush=True)
