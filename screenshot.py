# -*- coding: utf-8 -*-
import pyautogui
import pygetwindow as gw
import time

# Find and activate DevEco window
for w in gw.getAllWindows():
    if 'Clawdbot' in w.title or 'ClawdBot' in w.title or 'DevEco' in w.title:
        print(f"Found: {w.title}", flush=True)
        w.activate()
        time.sleep(0.5)
        break

# Take screenshot
time.sleep(0.5)
screenshot = pyautogui.screenshot()
screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
print("Screenshot saved to deveco_screenshot.png", flush=True)
