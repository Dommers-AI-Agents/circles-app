#!/usr/bin/env python3

import os
import re
from pathlib import Path

def find_api_calls(directory):
    """Find all APIService.shared.request calls that might be missing parameters."""
    
    # Pattern to match APIService.shared.request calls
    pattern = re.compile(
        r'APIService\.shared\.request\s*\(\s*'
        r'endpoint:\s*[^,]+,\s*'
        r'method:\s*[^,]+,\s*'
        r'(?:body:\s*[^,]+,\s*)?'
        r'(?:queryParams:\s*[^,]+,\s*)?'
        r'(?:headers:\s*[^,]+,\s*)?'
        r'requiresAuth:\s*(?:true|false)\s*'
        r'\)',
        re.DOTALL | re.MULTILINE
    )
    
    simplified_pattern = re.compile(
        r'APIService\.shared\.request\s*\(\s*'
        r'endpoint:\s*[^,]+,\s*'
        r'method:\s*[^,]+,\s*'
        r'requiresAuth:\s*(?:true|false)\s*'
        r'\)',
        re.DOTALL | re.MULTILINE
    )
    
    results = []
    
    for root, dirs, files in os.walk(directory):
        # Skip certain directories
        if any(skip in root for skip in ['.build', 'Pods', '.git', 'DerivedData']):
            continue
            
        for file in files:
            if file.endswith('.swift'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        
                    # Find all matches
                    for match in simplified_pattern.finditer(content):
                        # Check if this match has body, queryParams, or headers
                        match_text = match.group(0)
                        has_body = 'body:' in match_text
                        has_query = 'queryParams:' in match_text
                        has_headers = 'headers:' in match_text
                        
                        if not (has_body or has_query or has_headers):
                            # This is a simplified call
                            line_num = content[:match.start()].count('\n') + 1
                            results.append({
                                'file': file_path,
                                'line': line_num,
                                'match': match_text.strip()
                            })
                except Exception as e:
                    print(f"Error reading {file_path}: {e}")
    
    return results

def main():
    ios_dir = "/Users/wesleysgroi/circles-app/ios"
    
    print("Finding simplified APIService.shared.request calls...")
    results = find_api_calls(ios_dir)
    
    print(f"\nFound {len(results)} simplified calls:\n")
    
    # Group by file
    files_dict = {}
    for result in results:
        file_path = result['file']
        if file_path not in files_dict:
            files_dict[file_path] = []
        files_dict[file_path].append(result)
    
    for file_path, matches in files_dict.items():
        rel_path = os.path.relpath(file_path, ios_dir)
        print(f"\n{rel_path}:")
        for match in matches:
            print(f"  Line {match['line']}: {match['match'][:50]}...")

if __name__ == "__main__":
    main()