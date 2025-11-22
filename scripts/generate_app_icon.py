#!/usr/bin/env python3

"""
Generates the iPhone app icon based on the Landing Pages design.
Creates a 1024x1024 PNG image with:
- Dark background
- Dark gray rounded rectangle with subtle border
- White document icon in center
- "Landing Pages" text below icon
"""

from PIL import Image, ImageDraw, ImageFont
import os
import sys

def generate_app_icon():
    # Create 1024x1024 image with dark background
    size = (1024, 1024)
    image = Image.new('RGB', size, color=(13, 13, 13))  # Almost black
    draw = ImageDraw.Draw(image)
    
    # Calculate rounded rectangle dimensions (centered, with padding)
    padding = 200
    rect_x = padding
    rect_y = padding
    rect_width = size[0] - (padding * 2)
    rect_height = size[1] - (padding * 2)
    corner_radius = 80
    
    # Draw rounded rectangle with dark gray background
    rect = [rect_x, rect_y, rect_x + rect_width, rect_y + rect_height]
    
    # Draw dark gray rounded rectangle
    draw.rounded_rectangle(rect, radius=corner_radius, fill=(51, 51, 51))  # Dark gray
    
    # Draw subtle border (lighter gray outline)
    border_color = (89, 89, 89, 153)  # Lighter gray with transparency
    draw.rounded_rectangle(rect, radius=corner_radius, outline=(89, 89, 89), width=4)
    
    # Draw document icon
    icon_size = 280
    icon_center_x = rect_x + rect_width / 2
    icon_center_y = rect_y + rect_height / 2 - 80  # Position above center for text below
    icon_x = icon_center_x - icon_size / 2
    icon_y = icon_center_y - icon_size / 2
    
    # Document body dimensions
    body_padding = 40
    body_x = icon_x + body_padding
    body_y = icon_y + 60
    body_width = icon_size - (body_padding * 2)
    body_height = icon_size - 100
    fold_size = 50
    
    # Draw document outline (white)
    doc_outline = [
        (body_x, body_y),  # Top left
        (body_x + body_width - fold_size, body_y),  # Top right (before fold)
        (body_x + body_width, body_y + fold_size),  # Fold corner
        (body_x + body_width, body_y + body_height),  # Bottom right
        (body_x, body_y + body_height),  # Bottom left
    ]
    draw.polygon(doc_outline, outline='white', width=12)
    
    # Draw folded corner (filled white triangle)
    fold_triangle = [
        (body_x + body_width - fold_size, body_y),
        (body_x + body_width, body_y + fold_size),
        (body_x + body_width - fold_size, body_y + fold_size),
    ]
    draw.polygon(fold_triangle, fill='white')
    
    # Draw two horizontal lines inside document (representing text)
    line_padding = 40
    line_width = body_width - (line_padding * 2)
    line_spacing = 30
    line_y1 = body_y + body_height / 2 - line_spacing / 2
    line_y2 = body_y + body_height / 2 + line_spacing / 2
    
    # First line
    draw.line(
        [(body_x + line_padding, line_y1), (body_x + line_padding + line_width, line_y1)],
        fill='white',
        width=8
    )
    
    # Second line
    draw.line(
        [(body_x + line_padding, line_y2), (body_x + line_padding + line_width, line_y2)],
        fill='white',
        width=8
    )
    
    # Draw "Landing Pages" text
    try:
        # Try to use system font
        font_size = 72
        # Try different font paths for macOS
        font_paths = [
            '/System/Library/Fonts/Supplemental/SF-Pro-Text-Medium.otf',
            '/System/Library/Fonts/Helvetica.ttc',
            '/Library/Fonts/Arial.ttf',
        ]
        
        font = None
        for font_path in font_paths:
            if os.path.exists(font_path):
                try:
                    font = ImageFont.truetype(font_path, font_size)
                    break
                except:
                    continue
        
        if font is None:
            # Fallback to default font
            font = ImageFont.load_default()
    except:
        font = ImageFont.load_default()
    
    text = "Landing Pages"
    # Get text bounding box
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    # Position text below center
    text_x = icon_center_x - text_width / 2
    text_y = rect_y + rect_height / 2 + 120
    
    # Draw text
    draw.text((text_x, text_y), text, fill='white', font=font)
    
    return image

def main():
    # Get script directory and project root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    app_icon_dir = os.path.join(project_root, 'FLYR', 'Assets.xcassets', 'AppIcon.appiconset')
    
    # Ensure directory exists
    os.makedirs(app_icon_dir, exist_ok=True)
    
    # Generate icon
    print("🎨 Generating app icon...")
    icon = generate_app_icon()
    
    # Save icon
    output_path = os.path.join(app_icon_dir, 'AppIcon-1024.png')
    icon.save(output_path, 'PNG')
    
    print("✅ App icon generated successfully!")
    print(f"📍 Saved to: {output_path}")
    print("\nNext steps:")
    print("1. Open Xcode")
    print("2. Go to Assets.xcassets > AppIcon")
    print("3. Drag AppIcon-1024.png into the 1024x1024 slot")

if __name__ == '__main__':
    main()


