# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.2

print("Finding Project Structure dialog...", flush=True)

# Find the dialog window
for w in gw.getAllWindows():
    if 'Project Structure' in w.title:
        print(f"Found dialog: {w.title} at ({w.left}, {w.top}) size {w.width}x{w.height}", flush=True)
        # Activate and get position
        w.activate()
        time.sleep(0.3)
        
        # Calculate tab positions relative to dialog
        # Dialog content starts ~30px from top (title bar)
        # Tabs are about 35px from dialog top
        tab_y = w.top + 35
        
        # Signing Configs tab is about 350px from left edge of dialog
        signing_x = w.left + 350
        
        print(f"Clicking at ({signing_x}, {tab_y})", flush=True)
        pyautogui.click(signing_x, tab_y)
        time.sleep(0.5)
        break
else:
    # Dialog might have different title, try clicking based on screen
    print("Dialog not found by title, trying screen coordinates...", flush=True)
    # From screenshot, dialog is at ~(275, 100) with size ~900x550
    # Signing Configs tab is at about x=634 in absolute coords
    pyautogui.click(634, 152)
    time.sleep(0.5)

# Take screenshot
screenshot = pyautogui.screenshot()
screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
print("Screenshot saved", flush=True)
