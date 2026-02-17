#!/usr/bin/env python3
import pyautogui
import os

screenshot = pyautogui.screenshot()
path = r'C:\Users\Liuho\ClawdBotHarmony\build_status.png'
screenshot.save(path)
print(f"Screenshot saved to {path}")
