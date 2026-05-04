import json
import re

def fix_corrupted_json(raw_json_string):
    # Regex to find the content inside the "fix": "..." field
    # It grabs everything between the first quote after "fix": and the trailing quote before the next key
    pattern = re.compile(r'("fix"\s*:\s*")(.*?)("\s*,\s*"impacted_files")', re.DOTALL)
    
    def escape_diff_content(match):
        prefix = match.group(1)  # "fix": "
        diff_content = match.group(2)  # The raw git diff
        suffix = match.group(3)  # ", "impacted_files"
        
        # Escape literal quotes that are not already escaped
        fixed_content = diff_content.replace('"', '\"')
        
        return f"{prefix}{fixed_content}{suffix}"


    # Apply the regex fix to the raw string
    return pattern.sub(escape_diff_content, raw_json_string)
