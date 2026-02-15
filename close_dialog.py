# -*- coding: utf-8 -*-
import pyautogui
import time

print("Pressing Escape to close dialog...", flush=True)
pyautogui.press('escape')
time.sleep(0.5)
pyautogui.press('escape')
print("Done", flush=True)
