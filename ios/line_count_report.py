#!/usr/bin/env python3
import os
from collections import defaultdict

# Run the analysis
root_dir = '/Users/wesleysgroi/circles-app/ios/Circles-iOS-UIKit'
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
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    lines = [line for line in f.readlines() if line.strip()]
                    line_count = len(lines)
            except:
                line_count = 0
            
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
            stats[category]['lines'] += line_count
            total_files += 1
            total_lines += line_count

# Write results to file
with open('/Users/wesleysgroi/circles-app/ios/line_count_results.txt', 'w') as out:
    out.write("Circles iOS App - Lines of Code Analysis\n")
    out.write("=" * 60 + "\n\n")
    
    out.write("Breakdown by Directory/Category:\n")
    out.write("-" * 60 + "\n")
    out.write(f"{'Category':<25} {'Files':>10} {'Lines':>15}\n")
    out.write("-" * 60 + "\n")
    
    # Sort by lines of code
    sorted_stats = sorted(stats.items(), key=lambda x: x[1]['lines'], reverse=True)
    
    for category, data in sorted_stats:
        out.write(f"{category:<25} {data['files']:>10} {data['lines']:>15,}\n")
    
    out.write("-" * 60 + "\n")
    out.write(f"{'TOTAL':<25} {total_files:>10} {total_lines:>15,}\n")
    
    out.write("\n" + "=" * 60 + "\n")
    out.write(f"\nViewControllers found: {len(view_controllers)}\n")
    
    # Write list of ViewControllers
    out.write("\nList of ViewControllers:\n")
    for vc in sorted(view_controllers):
        out.write(f"  - {vc}\n")

print("Analysis complete. Results written to line_count_results.txt")