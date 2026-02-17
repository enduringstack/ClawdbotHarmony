# -*- coding: utf-8 -*-
import pygetwindow as gw
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

print("Looking for DevEco / ClawdbotHarmony window...")
windows = [w for w in gw.getAllWindows() if 'DevEco' in w.title or 'Clawdbot' in w.title or 'ClawdBot' in w.title]
for w in windows:
    print(f"Found: '{w.title}' at ({w.left}, {w.top}) size {w.width}x{w.height}")
    print(f"  Active: {w.isActive}, Minimized: {w.isMinimized}")

if not windows:
    print("DevEco Studio not running")
else:
    print(f"\nTotal: {len(windows)} window(s) found")
