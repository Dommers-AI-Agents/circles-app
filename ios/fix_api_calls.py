#!/usr/bin/env python3

import os
import re
from pathlib import Path

def fix_api_calls(file_path):
    """Fix APIService.shared.request calls to include all parameters explicitly."""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # Pattern to match simplified calls (without body, queryParams, or headers)
    # This pattern handles multi-line calls
    pattern = re.compile(
        r'(APIService\.shared\.request\s*\(\s*'
        r'endpoint:\s*[^,]+,\s*'
        r'method:\s*[^,]+,)\s*'
        r'(requiresAuth:\s*(?:true|false)\s*'
        r'\))',
        re.DOTALL | re.MULTILINE
    )
    
    def replacement(match):
        prefix = match.group(1)
        suffix = match.group(2)
        # Add the missing parameters
        return f"{prefix}\n            queryParams: nil,\n            body: nil,\n            headers: nil,\n            {suffix}"
    
    # Replace all matches
    content = pattern.sub(replacement, content)
    
    # Only write if changes were made
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False

def main():
    ios_dir = "/Users/wesleysgroi/circles-app/ios"
    
    # List of files to fix based on the search results
    files_to_fix = [
        "Circles-iOS-UIKit/Controllers/Circles/CirclesHomeViewController.swift",
        "Circles-iOS-UIKit/Controllers/Network/NetworkUsersViewController.swift",
        "Circles-iOS-UIKit/Controllers/Network/AllUsersListViewController.swift",
        "Circles-iOS-UIKit/Controllers/Network/ConnectionDetailViewController.swift",
        "Circles-iOS-UIKit/Controllers/Profile/FollowersListViewController.swift",
        "Circles-iOS-UIKit/Controllers/Profile/ProfileViewController.swift",
        "Circles-iOS-UIKit/Services/CategoryService.swift",
        "Circles-iOS-UIKit/Services/UserService.swift",
        "Circles-iOS-UIKit/Services/NotificationService.swift",
        "Circles-iOS-UIKit/Services/AuthService.swift",
        "Circles-iOS-UIKit/Services/CircleService.swift",
        "Circles-iOS-UIKit/Services/PlaceService.swift"
    ]
    
    fixed_count = 0
    
    print("Fixing APIService.shared.request calls...")
    
    for file_path in files_to_fix:
        full_path = os.path.join(ios_dir, file_path)
        if os.path.exists(full_path):
            if fix_api_calls(full_path):
                print(f"✓ Fixed: {file_path}")
                fixed_count += 1
            else:
                print(f"- No changes needed: {file_path}")
        else:
            print(f"✗ File not found: {file_path}")
    
    print(f"\nTotal files fixed: {fixed_count}")

if __name__ == "__main__":
    main()