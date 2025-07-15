#!/usr/bin/env python3
import os
import sys
from collections import defaultdict

def count_lines_in_file(file_path):
    """Count non-empty lines in a file"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            # Count non-empty lines
            return len([line for line in lines if line.strip()])
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0

def analyze_swift_files(root_dir):
    """Analyze all Swift files in the directory tree"""
    stats = defaultdict(lambda: {'files': 0, 'lines': 0})
    total_files = 0
    total_lines = 0
    view_controllers = []
    
    for root, dirs, files in os.walk(root_dir):
        # Skip test directories and build directories
        if 'Tests' in root or 'build' in root or '.xcodeproj' in root:
            continue
            
        for file in files:
            if file.endswith('.swift'):
                file_path = os.path.join(root, file)
                lines = count_lines_in_file(file_path)
                
                # Get relative path for categorization
                rel_path = os.path.relpath(file_path, root_dir)
                
                # Categorize by main directory
                if 'Controllers' in rel_path:
                    category = 'Controllers'
                    # Check if it's a ViewController
                    if 'ViewController' in file and file != 'BaseViewController.swift':
                        view_controllers.append(file)
                elif 'Services' in rel_path:
                    category = 'Services'
                elif 'Models' in rel_path:
                    category = 'Models'
                elif 'Views' in rel_path:
                    category = 'Views'
                elif 'Managers' in rel_path:
                    category = 'Managers'
                elif 'Utilities' in rel_path or 'Extensions' in rel_path:
                    category = 'Utilities/Extensions'
                elif 'Protocols' in rel_path:
                    category = 'Protocols'
                elif 'App' in rel_path:
                    category = 'App'
                else:
                    category = 'Other'
                
                stats[category]['files'] += 1
                stats[category]['lines'] += lines
                total_files += 1
                total_lines += lines
    
    return stats, total_files, total_lines, view_controllers

def main():
    root_dir = '/Users/wesleysgroi/circles-app/ios/Circles-iOS-UIKit'
    
    print("Analyzing Swift files in Circles iOS app...")
    print("=" * 60)
    
    stats, total_files, total_lines, view_controllers = analyze_swift_files(root_dir)
    
    # Print breakdown by category
    print("\nBreakdown by Directory/Category:")
    print("-" * 60)
    print(f"{'Category':<25} {'Files':>10} {'Lines':>15}")
    print("-" * 60)
    
    # Sort by lines of code
    sorted_stats = sorted(stats.items(), key=lambda x: x[1]['lines'], reverse=True)
    
    for category, data in sorted_stats:
        print(f"{category:<25} {data['files']:>10} {data['lines']:>15,}")
    
    print("-" * 60)
    print(f"{'TOTAL':<25} {total_files:>10} {total_lines:>15,}")
    
    # ViewControllers analysis
    print("\n" + "=" * 60)
    print(f"\nViewControllers that could benefit from BaseViewController pattern:")
    print(f"Total ViewControllers found: {len(view_controllers)}")
    print("-" * 60)
    
    # Group ViewControllers by category
    vc_categories = defaultdict(list)
    for vc in view_controllers:
        if 'Authentication' in vc or 'Login' in vc or 'Register' in vc:
            vc_categories['Authentication'].append(vc)
        elif 'Circle' in vc and 'Circles' not in vc:
            vc_categories['Circles'].append(vc)
        elif 'Place' in vc:
            vc_categories['Places'].append(vc)
        elif 'Network' in vc or 'Connection' in vc or 'User' in vc or 'Suggestion' in vc:
            vc_categories['Network'].append(vc)
        elif 'Message' in vc or 'Chat' in vc or 'Conversation' in vc:
            vc_categories['Messages'].append(vc)
        elif 'Profile' in vc or 'Settings' in vc:
            vc_categories['Profile'].append(vc)
        else:
            vc_categories['Other'].append(vc)
    
    for category, vcs in sorted(vc_categories.items()):
        print(f"\n{category} ({len(vcs)} ViewControllers):")
        for vc in sorted(vcs):
            print(f"  - {vc}")

if __name__ == "__main__":
    main()