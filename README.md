# KLayout to Wafer Map Converter

Converts GDS files (EP layer) to wafer map format for semiconductor testing.

## What it does
- Extracts die positions from layer 18/0 (EP layer) in GDS files
- **Auto-calculates die pitch** from actual die positions (NEW!)
- Generates wafer map in CSV/TXT format for test equipment (7YM)
- Marks edge dies (*) and good dies (?)

## Key Features

### Automatic Die Pitch Detection
The script now automatically calculates the die pitch (center-to-center spacing) from the actual die positions in the GDS file, rather than relying on manually configured die sizes. This ensures:
- **Accurate grid generation** - Dies are properly aligned to the grid
- **Dense wafer patterns** - Minimal empty cells in the output
- **No manual configuration** - Die spacing is detected automatically

### Diagnostic Output
The script provides detailed information during execution:
- Calculated pitch values (X and Y)
- Manual die size values (for comparison)
- Grid dimensions (rows × columns)
- Die counts (total, good dies, edge dies)

## Usage in KLayout

1. Open KLayout
2. Open your GDS file
3. Go to **Macros → Macro Development** (F5)
4. Create new **Ruby** macro
5. Paste the code from `Klayout_to_wafermapp.rb`
6. Update the configuration:
   ```ruby
   output_path = "C:/your/path/wafer_map.txt"
   die_size_x_mm = 1.1632  # Used as fallback if auto-detection fails
   die_size_y_mm = 1.1632  # Used as fallback if auto-detection fails
   wafer_diameter_mm = 150.0
