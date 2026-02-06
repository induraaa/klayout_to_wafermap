import csv
import re
from collections import defaultdict

def parse_wafer_test_file(filename):
    """Parse your wafer test format CSV file."""
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    # Parse header info
    wafer_info = {}
    test_data = {}
    grid_data = []
    
    in_header = True
    in_tests = False
    in_grid = False
    test_count = 0
    
    for i, line in enumerate(lines):
        line = line.strip()
        
        # Parse header
        if in_header and not line.startswith('"') and ',' in line:
            if ',' in line and not line.startswith('"'):
                parts = line.split(',')
                if len(parts) > 1:
                    wafer_info[parts[0].strip('"')] = parts[1].strip('"')
        
        # Detect test data section (lines starting with quoted numbers)
        if line.startswith('"') and ',' in line:
            parts = [p.strip('"') for p in line.split('","')]
            
            # Check if it's a test definition or grid data
            if len(parts) >= 2:
                try:
                    test_num = int(parts[0])
                    # It's test data
                    if len(parts) > 3:
                        in_tests = True
                        test_name = parts[1] if len(parts) > 1 else ""
                        status = parts[5] if len(parts) > 5 else ""
                        test_data[test_num] = {
                            'name': test_name,
                            'status': status,
                            'full_line': parts
                        }
                        test_count += 1
                except ValueError:
                    # It's grid data
                    if in_tests:
                        in_grid = True
                        in_tests = False
                    if in_grid:
                        grid_data.append([p.strip('"') for p in line.split('","')])
    
    return wafer_info, test_data, grid_data

def create_wafer_map_from_grid(grid_data):
    """Create a visual ASCII map from grid data."""
    if not grid_data:
        return []
    
    # Build ASCII visualization
    visual_map = []
    for row in grid_data:
        visual_row = ''.join(cell.strip('"') for cell in row if cell)
        if visual_row.strip():
            visual_map.append(visual_row)
    
    return visual_map

def analyze_die_status(grid_data):
    """Analyze die passes and failures from grid."""
    pass_count = 0
    fail_count = 0
    unknown_count = 0
    
    for row in grid_data:
        for cell in row:
            cell = cell.strip('"').strip()
            if cell == '*' or cell == 'o':
                pass_count += 1
            elif cell == '?' or cell == '!':
                fail_count += 1
            elif cell == '.':
                unknown_count += 1
    
    return pass_count, fail_count, unknown_count

def convert_gds2_to_wafer_map(input_file, output_file):
    """
    Convert GDS2/wafer test file to ASCII visualization with test map.
    """
    # Parse input
    wafer_info, test_data, grid_data = parse_wafer_test_file(input_file)
    
    # Create visual map
    visual_map = create_wafer_map_from_grid(grid_data)
    pass_count, fail_count, unknown_count = analyze_die_status(grid_data)
    
    # Write output
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        
        # Header section
        writer.writerow(['WAFER MAP VISUALIZATION'])
        writer.writerow([])
        
        # Wafer info
        writer.writerow(['Wafer Name:', wafer_info.get('0', '')])
        writer.writerow(['Die Pitch X:', wafer_info.get('2', '')])
        writer.writerow(['Die Pitch Y:', wafer_info.get('3', '')])
        writer.writerow(['Total Dies X:', wafer_info.get('6', '')])
        writer.writerow(['Total Dies Y:', wafer_info.get('7', '')])
        writer.writerow([])
        
        # Statistics
        writer.writerow(['Statistics'])
        writer.writerow(['Pass Dies:', pass_count])
        writer.writerow(['Fail Dies:', fail_count])
        writer.writerow(['Unknown Dies:', unknown_count])
        writer.writerow(['Total Dies:', pass_count + fail_count + unknown_count])
        writer.writerow([])
        
        # Test definitions
        writer.writerow(['Test Results'])
        writer.writerow(['Test #', 'Test Name', 'Status'])
        for test_num in sorted(test_data.keys()):
            test = test_data[test_num]
            writer.writerow([test_num, test['name'], test['status']])
        writer.writerow([])
        
        # Wafer map visualization
        writer.writerow(['Wafer Map'])
        for visual_row in visual_map:
            writer.writerow([visual_row])
        writer.writerow([])
        
        # Legend
        writer.writerow(['Legend'])
        writer.writerow(['Symbol', 'Meaning'])
        writer.writerow(['*', 'Passing Die'])
        writer.writerow(['?', 'Failed Die - Multiple Tests'])
        writer.writerow(['!', 'Failed Die - Critical'])
        writer.writerow(['.', 'Empty/Untested'])
        writer.writerow(['o', 'Passing Die - Alternate'])
        
    print(f"✓ Conversion complete: {output_file}")
    print(f"  - Pass Dies: {pass_count}")
    print(f"  - Fail Dies: {fail_count}")
    print(f"  - Unknown: {unknown_count}")

def main():
    input_file = "9PTVU6V7AA2T4Q-AT-SMA01A2-W0-V100 (3).txt"  # Your GDS2 file
    output_file = "wafer_map_output.csv"
    
    try:
        convert_gds2_to_wafer_map(input_file, output_file)
        
        # Also create a simple text visualization
        wafer_info, test_data, grid_data = parse_wafer_test_file(input_file)
        visual_map = create_wafer_map_from_grid(grid_data)
        
        print("\n" + "="*120)
        print("WAFER MAP VISUALIZATION")
        print("="*120)
        for row in visual_map:
            print(row)
        print("="*120)
        
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
