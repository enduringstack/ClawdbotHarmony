#!/usr/bin/env python3
"""Extract talk mode icons as clean circles with transparent background"""
from PIL import Image
import os
import math

media_dir = r'C:\Users\Liuho\ClawdBotHarmony\entry\src\main\resources\base\media'
source = os.path.join(media_dir, 'talkmode.jpg')

img = Image.open(source).convert('RGB')
width, height = img.size
print(f"Source size: {width}x{height}")

mid = width // 2

def extract_circle_clean(img, output_path, target_size=96):
    """Extract just the colored circle with transparent background"""
    pixels = img.load()
    w, h = img.size
    
    # Find colored pixels (green or red circle)
    colored_pixels = []
    for y in range(h):
        for x in range(w):
            r, g, b = pixels[x, y]
            is_green = g > 120 and g > r + 20
            is_red = r > 120 and r > g + 20
            if is_green or is_red:
                colored_pixels.append((x, y))
    
    if not colored_pixels:
        print(f"No colored circle found!")
        return
    
    # Find bounding box and center
    min_x = min(p[0] for p in colored_pixels)
    max_x = max(p[0] for p in colored_pixels)
    min_y = min(p[1] for p in colored_pixels)
    max_y = max(p[1] for p in colored_pixels)
    
    center_x = (min_x + max_x) // 2
    center_y = (min_y + max_y) // 2
    radius = max(max_x - min_x, max_y - min_y) // 2
    
    # Create output image with transparent background
    output = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))
    out_pixels = output.load()
    
    # Scale factor
    scale = target_size / (radius * 2)
    out_center = target_size // 2
    out_radius = target_size // 2
    
    # Copy pixels that are within the circle
    for out_y in range(target_size):
        for out_x in range(target_size):
            # Check if within circle
            dx = out_x - out_center
            dy = out_y - out_center
            dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= out_radius:
                # Map to source coordinates
                src_x = int(center_x + dx / scale)
                src_y = int(center_y + dy / scale)
                
                if 0 <= src_x < w and 0 <= src_y < h:
                    r, g, b = pixels[src_x, src_y]
                    # Check if this is part of the colored button (not background)
                    is_green = g > 100 and g > r
                    is_red = r > 100 and r > g
                    is_white = r > 200 and g > 200 and b > 200  # White phone icon
                    
                    if is_green or is_red or is_white:
                        out_pixels[out_x, out_y] = (r, g, b, 255)
    
    output.save(output_path, 'PNG')
    print(f"Saved {output_path} ({target_size}x{target_size})")

# Process both icons - size 32 to match emoji icons
left_img = img.crop((0, 0, mid, height))
extract_circle_clean(left_img, os.path.join(media_dir, 'ic_talk_mode.png'), 96)

right_img = img.crop((mid, 0, width, height))
extract_circle_clean(right_img, os.path.join(media_dir, 'ic_hangup.png'), 96)

print("Done!")
