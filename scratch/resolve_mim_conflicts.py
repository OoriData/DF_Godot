import re
import sys

def resolve_conflicts(content):
    # Pattern to match git conflict markers
    # We want to pick the "incoming" side (fd0dad3)
    pattern = re.compile(r'<<<<<<< HEAD\n(.*?)\n?=======\n(.*?)\n?>>>>>>> fd0dad380d911a788cc20658912c5aa541c42c61', re.DOTALL)
    
    def replace_func(match):
        return match.group(2)
    
    resolved = pattern.sub(replace_func, content)
    return resolved

if __name__ == "__main__":
    file_path = "/Users/choccy/dev/DF_Godot/Scripts/Map/map_interaction_manager.gd"
    with open(file_path, 'r') as f:
        content = f.read()
    
    resolved_content = resolve_conflicts(content)
    
    with open(file_path, 'w') as f:
        f.write(resolved_content)
    
    print("Resolved conflicts in map_interaction_manager.gd")
