import os
import glob

# Define the base directory
base_dir = '/Users/wesleysgroi/circles-app/ios/Circles-iOS-UIKit'

# Categories to analyze
categories = {
    'Controllers': 'Controllers/**/*.swift',
    'Services': 'Services/*.swift',
    'Models': 'Models/*.swift',
    'Views': 'Views/**/*.swift',
    'Managers': 'Managers/*.swift',
    'Utilities/Extensions': 'Utilities/**/*.swift',
    'Extensions': 'Extensions/*.swift',
    'Protocols': 'Protocols/*.swift',
    'App': 'App/*.swift'
}

# Function to count lines in a file
def count_lines(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return len([line for line in f.readlines() if line.strip()])
    except:
        return 0

# Analyze each category
results = {}
total_files = 0
total_lines = 0
view_controllers = []

for category, pattern in categories.items():
    full_pattern = os.path.join(base_dir, pattern)
    files = glob.glob(full_pattern, recursive=True)
    
    category_files = 0
    category_lines = 0
    
    for file in files:
        if file.endswith('.swift'):
            lines = count_lines(file)
            category_files += 1
            category_lines += lines
            
            # Track ViewControllers
            filename = os.path.basename(file)
            if 'ViewController' in filename and filename != 'BaseViewController.swift':
                view_controllers.append(filename)
    
    if category_files > 0:
        results[category] = {'files': category_files, 'lines': category_lines}
        total_files += category_files
        total_lines += category_lines

# Handle other Swift files
other_files = glob.glob(os.path.join(base_dir, '*.swift'))
other_count = 0
other_lines = 0
for file in other_files:
    if file.endswith('.swift'):
        lines = count_lines(file)
        other_count += 1
        other_lines += lines

if other_count > 0:
    results['Other'] = {'files': other_count, 'lines': other_lines}
    total_files += other_count
    total_lines += other_lines

# Sort results by lines of code
sorted_results = sorted(results.items(), key=lambda x: x[1]['lines'], reverse=True)

# Print results
print("Circles iOS App - Lines of Code Analysis")
print("=" * 60)
print()
print("Breakdown by Directory/Category:")
print("-" * 60)
print(f"{'Category':<25} {'Files':>10} {'Lines':>15}")
print("-" * 60)

for category, data in sorted_results:
    print(f"{category:<25} {data['files']:>10} {data['lines']:>15:,}")

print("-" * 60)
print(f"{'TOTAL':<25} {total_files:>10} {total_lines:>15:,}")

# ViewControllers analysis
print("\n" + "=" * 60)
print(f"\nViewControllers that could benefit from BaseViewController pattern:")
print(f"Total ViewControllers found: {len(view_controllers)}")
print("-" * 60)

# Categorize ViewControllers
vc_categories = {
    'Authentication': [],
    'Circles': [],
    'Places': [],
    'Network': [],
    'Messages': [],
    'Profile': [],
    'Other': []
}

for vc in view_controllers:
    if 'Login' in vc or 'Register' in vc or 'Email' in vc:
        vc_categories['Authentication'].append(vc)
    elif 'Circle' in vc and 'Circles' not in vc:
        vc_categories['Circles'].append(vc)
    elif 'Place' in vc:
        vc_categories['Places'].append(vc)
    elif 'Network' in vc or 'Connection' in vc or 'User' in vc or 'Suggestion' in vc or 'Shared' in vc:
        vc_categories['Network'].append(vc)
    elif 'Message' in vc or 'Chat' in vc or 'Conversation' in vc:
        vc_categories['Messages'].append(vc)
    elif 'Profile' in vc or 'Settings' in vc or 'Change' in vc or 'Edit' in vc or 'Share' in vc or 'Followers' in vc:
        vc_categories['Profile'].append(vc)
    else:
        vc_categories['Other'].append(vc)

for category, vcs in vc_categories.items():
    if vcs:
        print(f"\n{category} ({len(vcs)} ViewControllers):")
        for vc in sorted(vcs):
            print(f"  - {vc}")

# Additional stats
print("\n" + "=" * 60)
print("\nAdditional Statistics:")
print(f"- Average lines per file: {total_lines // total_files if total_files > 0 else 0:,}")
print(f"- Largest category: {sorted_results[0][0]} with {sorted_results[0][1]['lines']:,} lines")
print(f"- Number of ViewControllers: {len(view_controllers)}")