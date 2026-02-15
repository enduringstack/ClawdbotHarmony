#!/usr/bin/env python3
"""Re-split and crop talk mode icons from original image"""
from PIL import Image
import os

media_dir = r'C:\Users\Liuho\ClawdBotHarmony\entry\src\main\resources\base\media'
source = os.path.join(media_dir, 'talkmode.jpg')

img = Image.open(source)
width, height = img.size
print(f"Source size: {width}x{height}")

# Split in half
mid = width // 2

# Left icon (talk mode - green)
left_img = img.crop((0, 0, mid, height))

# Right icon (hangup - red)  
right_img = img.crop((mid, 0, width, height))

def extract_circle(img, output_path, target_size=128):
    """Extract the circular button and save as square PNG"""
    img = img.convert('RGBA')
    
    # Find the bounding box of non-white pixels
    pixels = img.load()
    min_x, min_y = img.width, img.height
    max_x, max_y = 0, 0
    
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = pixels[x, y]
            # Check if not white/transparent background
            if not (r > 240 and g > 240 and b > 240):
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    
    # Add padding and make square
    padding = 5
    min_x = max(0, min_x - padding)
    min_y = max(0, min_y - padding)
    max_x = min(img.width, max_x + padding)
    max_y = min(img.height, max_y + padding)
    
    # Make it square
    w = max_x - min_x
    h = max_y - min_y
    size = max(w, h)
    
    center_x = (min_x + max_x) // 2
    center_y = (min_y + max_y) // 2
    
    crop_left = center_x - size // 2
    crop_top = center_y - size // 2
    crop_right = crop_left + size
    crop_bottom = crop_top + size
    
    # Ensure bounds
    if crop_left < 0:
        crop_right -= crop_left
        crop_left = 0
    if crop_top < 0:
        crop_bottom -= crop_top
        crop_top = 0
    
    cropped = img.crop((crop_left, crop_top, crop_right, crop_bottom))
    
    # Resize to target size
    resized = cropped.resize((target_size, target_size), Image.LANCZOS)
    resized.save(output_path, 'PNG')
    print(f"Saved {output_path} ({target_size}x{target_size})")

# Extract and save both icons
extract_circle(left_img, os.path.join(media_dir, 'ic_talk_mode.png'), 128)
extract_circle(right_img, os.path.join(media_dir, 'ic_hangup.png'), 128)

print("Done!")
