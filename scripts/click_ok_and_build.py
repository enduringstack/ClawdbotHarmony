# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.3

print("Step 1: Clicking OK button...", flush=True)

# Find Project Structure dialog and click OK
for w in gw.getAllWindows():
    if 'Project Structure' in w.title:
        # OK button is at bottom right of dialog
        # Dialog size is ~816x448, OK button is about 70px from right, 30px from bottom
        ok_x = w.left + w.width - 70
        ok_y = w.top + w.height - 30
        
        print(f"Clicking OK at ({ok_x}, {ok_y})", flush=True)
        pyautogui.click(ok_x, ok_y)
        time.sleep(1)
        break

print("Step 2: Waiting for dialog to close...", flush=True)
time.sleep(2)

print("Step 3: Triggering Run...", flush=True)

# Find DevEco main window
for w in gw.getAllWindows():
    if 'ClawdbotHarm' in w.title:
        print(f"Found DevEco: {w.title}", flush=True)
        # Use Alt+R to open Run menu, then Enter
        pyautogui.hotkey('alt', 'r')
        time.sleep(0.5)
        pyautogui.press('enter')
        print("Run triggered!", flush=True)
        break

print("Done!", flush=True)
