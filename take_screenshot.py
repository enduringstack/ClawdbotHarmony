# -*- coding: utf-8 -*-
import pyautogui
import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = False
try:
    screenshot = pyautogui.screenshot()
    screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
    print("Screenshot saved", flush=True)
except Exception as e:
    print(f"Screenshot failed: {e}", flush=True)
