import pya
import csv
import math

# ==================== CONFIGURATION ====================
# TODO: Update these paths on your work PC
GDS_FILE_PATH = r"C:\path\to\your\file.gds"
OUTPUT_TXT_PATH = r"C:\path\to\output\wafer_map.txt"

# TODO: Ask Steve for these values
DIE_SIZE_X_MM = 3.0  # Die width in mm (CHANGE THIS!)
DIE_SIZE_Y_MM = 3.0  # Die height in mm (CHANGE THIS!)
WAFER_DIAMETER_MM = 150.0  # Wafer diameter in mm (probably 150mm or 200mm)

# EP Layer number (from your .lyp file)
EP_LAYER = 18
EP_DATATYPE = 0

# ==================== FUNCTIONS ====================

def extract_die_positions_from_gds(gds_file, layer_num, datatype):
    """
    Extract die positions from the EP layer in the GDS file.
    Returns a list of (x, y) tuples in millimeters.
    """
    print(f"Loading GDS file: {gds_file}")
    
    # Load the GDS file
    layout = pya.Layout()
    layout.read(gds_file)
    
    # Get the top cell
    top_cell = layout.top_cell()
    print(f"Top cell: {top_cell.name}")
    
    # Access the EP layer
    layer_info = pya.LayerInfo(layer_num, datatype)
    layer_index = layout.layer(layer_info)
    
    if layer_index is None:
        print(f"ERROR: Layer {layer_num}/{datatype} not found!")
        return []
    
    # Get all shapes on the EP layer
    shapes = top_cell.shapes(layer_index)
    
    die_positions = []
    
    # Iterate through all shapes on EP layer
    for shape in shapes.each():
        if shape.is_box() or shape.is_polygon():
            # Get the bounding box center
            bbox = shape.bbox()
            center_x = (bbox.left + bbox.right) / 2.0
            center_y = (bbox.bottom + bbox.top) / 2.0
            
            # Convert database units to millimeters
            # KLayout uses database units (usually microns or nanometers)
            center_x_mm = center_x * layout.dbu / 1000.0  # Convert to mm
            center_y_mm = center_y * layout.dbu / 1000.0  # Convert to mm
            
            die_positions.append((center_x_mm, center_y_mm))
    
    print(f"Found {len(die_positions)} die positions on layer {layer_num}/{datatype}")
    return die_positions


def create_wafer_map_grid(die_positions, die_size_x, die_size_y, wafer_diameter):
    """
    Convert die positions to a grid representing the wafer.
    Returns a 2D list where each cell is a die status symbol.
    """
    if not die_positions:
        print("ERROR: No die positions found!")
        return []
    
    # Find the range of die positions
    x_coords = [pos[0] for pos in die_positions]
    y_coords = [pos[1] for pos in die_positions]
    
    min_x = min(x_coords)
    max_x = max(x_coords)
    min_y = min(y_coords)
    max_y = max(y_coords)
    
    print(f"Die position range: X=[{min_x:.2f}, {max_x:.2f}], Y=[{min_y:.2f}, {max_y:.2f}]")
    
    # Calculate grid dimensions
    grid_cols = int(round((max_x - min_x) / die_size_x)) + 1
    grid_rows = int(round((max_y - min_y) / die_size_y)) + 1
    
    print(f"Grid size: {grid_cols} cols x {grid_rows} rows")
    
    # Initialize grid with '.' (no die)
    grid = [['.' for _ in range(grid_cols)] for _ in range(grid_rows)]
    
    # Wafer center (assuming center is at origin or average of positions)
    center_x = (min_x + max_x) / 2.0
    center_y = (min_y + max_y) / 2.0
    wafer_radius = wafer_diameter / 2.0
    
    # Place die on the grid
    for x, y in die_positions:
        # Calculate grid indices
        col = int(round((x - min_x) / die_size_x))
        row = int(round((y - min_y) / die_size_y))
        
        # Check if within grid bounds
        if 0 <= row < grid_rows and 0 <= col < grid_cols:
            # Calculate distance from wafer center
            dist_from_center = math.sqrt((x - center_x)**2 + (y - center_y)**2)
            
            # Determine die type based on distance from center
            if dist_from_center > wafer_radius * 0.95:
                grid[row][col] = '*'  # Edge die
            else:
                grid[row][col] = '?'  # Good die
    
    return grid


def write_wafer_map_to_txt(grid, output_file, wafer_info):
    """
    Write the wafer map grid to a text file in the format matching the example.
    """
    print(f"Writing wafer map to: {output_file}")
    
    with open(output_file, 'w') as f:
        # Write header (simplified - you can add more details if needed)
        f.write(f'"{wafer_info["name"]}",{wafer_info["cols"]},"{wafer_info["units"]}","{wafer_info["orientation"]}",')
        f.write(f'"{wafer_info["die_width"]}","{wafer_info["die_height"]}",{wafer_info["rows"]},{wafer_info["cols"]},')
        f.write(f'"0","0"\n')
        
        # Write some default header lines (matching the example format)
        f.write('"44","4"\n')
        f.write('"0"\n')
        f.write('"1","4"\n')
        f.write('"POST"\n')
        f.write('0\n0\n0\n"FALSE"\n0\n0\n"FALSE"\n"0"\n"0"\n"7038"\n')
        f.write('"RVD","RVD","RVD"\n"FALSE"\n""\n"0"\n"100:6"\n')
        f.write('"RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD"\n')
        f.write('""\n""\n')
        f.write('"RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD","RVD"\n')
        f.write('"25"\n')
        
        # Write bin definitions (simplified)
        f.write('"1","PASS","","0","0","PASS",65280,"0","0","False"\n')
        f.write('"2","PASS","","0","0","PASS",65280,"0","0","False"\n')
        # ... (add more bins if needed)
        
        # Write the actual wafer map grid (THIS IS THE IMPORTANT PART)
        for row in reversed(grid):  # Reverse to match top-to-bottom orientation
            line = ','.join(f'"{cell}"' for cell in row)
            f.write(line + '\n')
    
    print(f"Wafer map written successfully! Total rows: {len(grid)}")


# ==================== MAIN EXECUTION ====================

def main():
    print("=" * 60)
    print("GDS to Wafer Map Converter")
    print("=" * 60)
    
    # Step 1: Extract die positions from GDS
    die_positions = extract_die_positions_from_gds(
        GDS_FILE_PATH, 
        EP_LAYER, 
        EP_DATATYPE
    )
    
    if not die_positions:
        print("ERROR: No die found! Check the GDS file and layer number.")
        return
    
    # Step 2: Create wafer map grid
    grid = create_wafer_map_grid(
        die_positions, 
        DIE_SIZE_X_MM, 
        DIE_SIZE_Y_MM, 
        WAFER_DIAMETER_MM
    )
    
    if not grid:
        print("ERROR: Could not create wafer map grid!")
        return
    
    # Step 3: Prepare wafer info for output file
    wafer_info = {
        "name": "9PTVU6V7AA2T4Q-AT-SMA01A2-W0-V100",  # Update this
        "cols": len(grid[0]) if grid else 0,
        "rows": len(grid),
        "units": "METRIC",
        "orientation": "BOTTOM",
        "die_width": f"{DIE_SIZE_X_MM}",
        "die_height": f"{DIE_SIZE_Y_MM}"
    }
    
    # Step 4: Write to output file
    write_wafer_map_to_txt(grid, OUTPUT_TXT_PATH, wafer_info)
    
    print("=" * 60)
    print("DONE! Check the output file.")
    print("=" * 60)


if __name__ == "__main__":
    main()