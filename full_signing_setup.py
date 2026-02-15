# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.3

def log(msg):
    print(msg, flush=True)

log("Step 1: Opening Project Structure...")

# Find DevEco window and activate
for w in gw.getAllWindows():
    if 'ClawdbotHarm' in w.title or 'DevEco' in w.title:
        log(f"Found: {w.title}")
        w.activate()
        time.sleep(0.5)
        break

# Open Project Structure with Ctrl+Alt+Shift+S
pyautogui.hotkey('ctrl', 'alt', 'shift', 's')
time.sleep(1.5)

log("Step 2: Looking for Project Structure dialog...")

# Find and click Signing Configs tab
for w in gw.getAllWindows():
    if 'Project Structure' in w.title:
        log(f"Found dialog at ({w.left}, {w.top}) size {w.width}x{w.height}")
        w.activate()
        time.sleep(0.3)
        
        # Signing Configs tab is about 330px from left, 35px from top
        tab_x = w.left + 330
        tab_y = w.top + 35
        
        log(f"Step 3: Clicking Signing Configs at ({tab_x}, {tab_y})")
        pyautogui.click(tab_x, tab_y)
        time.sleep(0.5)
        break
else:
    log("Dialog not found!")

# Take screenshot
screenshot = pyautogui.screenshot()
screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
log("Screenshot saved")
