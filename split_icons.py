#!/usr/bin/env python3
"""Split the combined talk mode icon into two separate icons"""
from PIL import Image
import os

# Load the combined image
img_path = r'C:\Users\Liuho\ClawdBotHarmony\entry\src\main\resources\base\media\talkmode.jpg'
output_dir = r'C:\Users\Liuho\ClawdBotHarmony\entry\src\main\resources\base\media'

img = Image.open(img_path)
width, height = img.size
print(f"Image size: {width}x{height}")

# Split in half - left is talk, right is hangup
mid = width // 2

# Crop left half (talk mode - green)
talk_icon = img.crop((0, 0, mid, height))
talk_path = os.path.join(output_dir, 'ic_talk_mode.png')
talk_icon.save(talk_path, 'PNG')
print(f"Saved: {talk_path}")

# Crop right half (hangup - red)
hangup_icon = img.crop((mid, 0, width, height))
hangup_path = os.path.join(output_dir, 'ic_hangup.png')
hangup_icon.save(hangup_path, 'PNG')
print(f"Saved: {hangup_path}")

print("Done!")
