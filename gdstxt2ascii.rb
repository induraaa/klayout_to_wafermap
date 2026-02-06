import re
from collections import defaultdict

def parse_gds2_wafer_map(filename):
    """
    Parse GDS2 text format with SREF (structure references) for wafer maps.
    Returns a dictionary of structures and their placements.
    """
    with open(filename, 'r') as f:
        content = f.read()
    
    structures = {}
    current_struct = None
    placements = defaultdict(list)  # struct_name -> list of (x, y) placements
    
    lines = content.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # Parse structure definitions
        if line.startswith('STRNAME'):
            current_struct = line.split()[1]
            structures[current_struct] = {'type': 'cell'}
        
        # Parse structure references (SREF)
        elif line.startswith('SREF'):
            i += 1
            sref_name = None
            x, y = 0, 0
            
            # Look ahead for SNAME and XY
            while i < len(lines):
                subline = lines[i].strip()
                
                if subline.startswith('SNAME'):
                    sref_name = subline.split()[1]
                elif subline.startswith('XY'):
                    # Parse coordinates: "XY x: y" format
                    xy_part = subline.replace('XY', '').strip()
                    # Handle both "x: y" and "x y" formats
                    xy_part = xy_part.replace(':', ' ')
                    coords = re.findall(r'-?\d+', xy_part)
                    if len(coords) >= 2:
                        x = int(coords[0])
                        y = int(coords[1])
                elif subline.startswith('ENDEL'):
                    if sref_name and current_struct:
                        placements[current_struct].append((x, y, sref_name))
                    i -= 1  # Back up to process ENDEL normally
                    break
                
                i += 1
        
        i += 1
    
    return structures, placements

def create_wafer_map_visualization(placements, structure_name, grid_width=120, grid_height=60):
    """
    Create ASCII visualization of wafer map from placements.
    """
    if structure_name not in placements or not placements[structure_name]:
        print(f"No placements found for {structure_name}")
        return None
    
    positions = placements[structure_name]
    
    # Extract coordinates
    x_coords = [x for x, y, _ in positions]
    y_coords = [y for x, y, _ in positions]
    
    min_x = min(x_coords)
    max_x = max(x_coords)
    min_y = min(y_coords)
    max_y = max(y_coords)
    
    # Normalize to grid
    if max_x - min_x == 0:
        scale_x = 1
    else:
        scale_x = (grid_width - 2) / (max_x - min_x)
    
    if max_y - min_y == 0:
        scale_y = 1
    else:
        scale_y = (grid_height - 2) / (max_y - min_y)
    
    # Create grid
    grid = [['.' for _ in range(grid_width)] for _ in range(grid_height)]
    
    # Place elements
    for x, y, ref_name in positions:
        # Normalize coordinates
        norm_x = int((x - min_x) * scale_x)
        norm_y = int((max_y - y) * scale_y)  # Flip Y
        
        if 0 <= norm_x < grid_width and 0 <= norm_y < grid_height:
            # Use different symbols for different references
            if 'subdef1' in ref_name:
                symbol = '▓'  # or '#'
            elif 'subdef2' in ref_name:
                symbol = '░'  # or '@'
            elif 'subdef3' in ref_name:
                symbol = '▒'  # or '*'
            else:
                symbol = '●'
            
            grid[norm_y][norm_x] = symbol
    
    return grid

def print_wafer_map(grid, structure_name, positions_count):
    """Print the ASCII wafer map with border and labels."""
    print("\n" + "="*len(grid[0]))
    print(f"WAFER MAP: {structure_name}")
    print(f"Total Die Count: {positions_count}")
    print("="*len(grid[0]))
    
    for row in grid:
        print(''.join(row))
    
    print("="*len(grid[0]))
    print("Legend: ▓=subdef1  ░=subdef2  ▒=subdef3  ●=other")
    print("="*len(grid[0]) + "\n")

def print_coordinate_map(placements, structure_name):
    """Print detailed coordinate list."""
    if structure_name not in placements:
        return
    
    positions = placements[structure_name]
    print(f"\n{structure_name} - Placement Coordinates:")
    print("-" * 60)
    print(f"{'#':<4} {'X Coord':<15} {'Y Coord':<15} {'Reference':<20}")
    print("-" * 60)
    
    for idx, (x, y, ref) in enumerate(positions, 1):
        print(f"{idx:<4} {x:<15} {y:<15} {ref:<20}")
    
    print(f"\nTotal placements: {len(positions)}")

def main():
    # Configuration
    input_file = "your_layout.txt"  # Change to your actual file
    target_structure = "PTVSA2-xx-0xB_1205"
    grid_w = 120
    grid_h = 60
    
    print(f"Parsing {input_file}...")
    try:
        structures, placements = parse_gds2_wafer_map(input_file)
        
        print(f"\nStructures found: {list(structures.keys())}")
        print(f"Structures with placements: {list(placements.keys())}")
        
        if target_structure in placements:
            positions = placements[target_structure]
            print(f"\nFound {len(positions)} placements in {target_structure}")
            
            # Create and display ASCII map
            grid = create_wafer_map_visualization(
                placements, target_structure, 
                grid_width=grid_w, grid_height=grid_h
            )
            
            if grid:
                print_wafer_map(grid, target_structure, len(positions))
            
            # Print detailed coordinates
            print_coordinate_map(placements, target_structure)
        else:
            print(f"\n{target_structure} not found!")
            print(f"Available structures: {list(placements.keys())}")
    
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
