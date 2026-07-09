import os
import glob

def replace_font_size():
    directory = "renderer/src/styles"
    files = glob.glob(f"{directory}/*.tsx")
    
    for file_path in files:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Replace fontSize: `${Math.round(24 * sf)}px` with 16
        new_content = content.replace(
            "fontSize: `${Math.round(24 * sf)}px`", 
            "fontSize: `${Math.round(16 * sf)}px`"
        )
        
        # In MrBeastStyle: fontSize: isActive ? `${Math.round(24 * sf)}px` : `${Math.round(24 * sf)}px`
        new_content = new_content.replace(
            "fontSize: isActive ? `${Math.round(24 * sf)}px` : `${Math.round(24 * sf)}px`",
            "fontSize: isActive ? `${Math.round(16 * sf)}px` : `${Math.round(16 * sf)}px`"
        )

        # Medusa and Buzz overrides (scale down by roughly 16/24 if we want)
        # But simple replacement is enough for most styles.

        if new_content != content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f"Updated {file_path}")

replace_font_size()
