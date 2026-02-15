# -*- coding: utf-8 -*-
"""
Auto click Signing Configs tab and configure signing
"""
import pyautogui
import pygetwindow as gw
import time
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(msg, flush=True)

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.2

def main():
    log("Finding DevEco window...")
    
    for w in gw.getAllWindows():
        if 'Clawdbot' in w.title or 'Project Structure' in w.title:
            log(f"Found: {w.title}")
            w.activate()
            time.sleep(0.5)
            break
    
    # Take screenshot to find tab position
    log("Looking for Signing Configs tab...")
    
    # Try to locate and click on "Signing Configs" text
    # Based on previous screenshot, the tabs are at y~152
    # Basic Info ~443, Dependencies ~528, Signing Configs ~634
    
    # Click on Signing Configs tab (approximate position)
    log("Clicking Signing Configs tab...")
    pyautogui.click(634, 152)
    time.sleep(0.5)
    
    # If that didn't work, try clicking by image or using keyboard
    # Tab through: press Tab to move focus, or click directly
    
    log("Done! Taking screenshot...")
    screenshot = pyautogui.screenshot()
    screenshot.save(r"C:\Users\Liuho\ClawdBotHarmony\deveco_screenshot.png")
    log("Screenshot saved")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
