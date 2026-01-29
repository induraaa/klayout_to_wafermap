# KLayout to Wafer Map Converter

Converts GDS files (EP layer) to wafer map format for semiconductor testing.

## What it does
- Extracts die positions from layer 18/0 (EP layer) in GDS files
- Generates wafer map in CSV/TXT format for test equipment (7YM)
- Marks edge dies (*) and good dies (?)

## Usage in KLayout

1. Open KLayout
2. Open your GDS file
3. Go to **Macros → Macro Development** (F5)
4. Create new **Ruby** macro
5. Paste the code from `wafermap_converter.rb`
6. Update the configuration:
   ```ruby
   output_path = "C:/your/path/wafer_map.txt"
   die_size_x_mm = 1.1632
   die_size_y_mm = 1.1632
   wafer_diameter_mm = 150.0
