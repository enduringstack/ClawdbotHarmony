# -*- coding: utf-8 -*-
import pyautogui
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.2

print("Clicking Signing Configs tab...", flush=True)

# From screenshot: Signing Configs is at approximately x=385, y=209
pyautogui.click(385, 209)
time.sleep(0.5)

# Take screenshot
screenshot = pyautogui.screenshot()
screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
print("Screenshot saved", flush=True)
