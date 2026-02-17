# -*- coding: utf-8 -*-
import pyautogui
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.2

print("Clicking on Signing Configs tab...", flush=True)

# From screenshot: Signing Configs tab is around x=630, y=152
# But let's try to click directly on the text
pyautogui.click(634, 152)
time.sleep(0.5)

# Take screenshot
screenshot = pyautogui.screenshot()
screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
print("Screenshot saved", flush=True)
