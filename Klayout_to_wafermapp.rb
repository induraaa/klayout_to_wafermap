# CONFIGURATION - CHANGE THESE!
output_path = "C:/temp/wafer_map.txt"
wafer_diameter_mm = 150.0
ep_layer = 18
ep_datatype = 0

# Get current layout
def get_current_layout
  app = RBA::Application.instance
  mw = app.main_window
  view = mw.current_view
  
  if view.nil?
    RBA::MessageBox.warning("Error", "No layout open!", RBA::MessageBox::Ok)
    return nil, nil
  end
  
  cv = view.active_cellview
  return cv.layout, cv.cell
end

# Extract die positions
def extract_die_positions(ep_layer, ep_datatype)
  layout, cell = get_current_layout
  return [] if layout.nil?
  
  layer_idx = layout.layer(ep_layer, ep_datatype)
  shapes = cell.shapes(layer_idx)
  
  positions = []
  count = 0
  
  shapes.each do |shape|
    count += 1
    bbox = shape.bbox
    
    cx = (bbox.left + bbox.right) / 2.0
    cy = (bbox.bottom + bbox.top) / 2.0
    
    cx_mm = cx * layout.dbu / 1000.0
    cy_mm = cy * layout.dbu / 1000.0
    
    positions << [cx_mm, cy_mm]
  end
  
  puts "Found shapes: #{count}"
  puts "Die positions: #{positions.length}"
  
  return positions
end

# Auto-calculate die pitch using nearest neighbor with statistical filtering
def calculate_pitch_robust(positions, sample_size = 300)
  return [1.78, 1.81] if positions.length < 10
  
  sample = positions.take([sample_size, positions.length].min)
  
  x_distances = []
  y_distances = []
  
  # For each sample die, find nearest neighbor in X and Y direction
  sample.each_with_index do |pos, i|
    nearest_x = nil
    nearest_y = nil
    
    positions.each_with_index do |other, j|
      next if i == j
      
      dx = (other[0] - pos[0]).abs
      dy = (other[1] - pos[1]).abs
      
      # Nearest in X direction (must be in same row - Y within 0.4mm)
      if dy < 0.4 && dx > 0.1
        nearest_x = dx if nearest_x.nil? || dx < nearest_x
      end
      
      # Nearest in Y direction (must be in same column - X within 0.4mm)
      if dx < 0.4 && dy > 0.1
        nearest_y = dy if nearest_y.nil? || dy < nearest_y
      end
    end
    
    x_distances << nearest_x if nearest_x && nearest_x < 5.0
    y_distances << nearest_y if nearest_y && nearest_y < 5.0
  end
  
  # Use median to avoid outliers
  pitch_x = x_distances.empty? ? 1.78 : median(x_distances)
  pitch_y = y_distances.empty? ? 1.81 : median(y_distances)
  
  puts "Auto-detected pitch - X: #{pitch_x.round(4)} mm (from #{x_distances.length} samples)"
  puts "Auto-detected pitch - Y: #{pitch_y.round(4)} mm (from #{y_distances.length} samples)"
  
  return [pitch_x, pitch_y]
end

def median(array)
  return 0 if array.empty?
  sorted = array.sort
  len = sorted.length
  (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
end

# Create grid with improved mapping
def create_grid(positions, wafer_diameter_mm)
  return [] if positions.empty?
  
  # Auto-calculate pitch
  pitch_x, pitch_y = calculate_pitch_robust(positions)
  
  x_list = positions.map { |p| p[0] }
  y_list = positions.map { |p| p[1] }
  
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max
  
  puts "X range: #{min_x.round(3)} to #{max_x.round(3)} mm"
  puts "Y range: #{min_y.round(3)} to #{max_y.round(3)} mm"
  
  cols = ((max_x - min_x) / pitch_x).round + 1
  rows = ((max_y - min_y) / pitch_y).round + 1
  
  puts "Grid: #{cols} cols x #{rows} rows"
  
  # Safety check
  if cols > 300 || rows > 300
    puts "ERROR: Grid too large! Check pitch calculation."
    return [], pitch_x, pitch_y
  end
  
  # Initialize grid with '.'
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  # Wafer center calculation
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  puts "Wafer center: (#{cx.round(2)}, #{cy.round(2)}) mm"
  puts "Radius: #{radius} mm"
  
  # Map each die with improved snapping - try multiple strategies
  mapped_count = 0
  edge_count = 0
  skipped = []
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    # Calculate exact grid position
    col_exact = (x - min_x) / pitch_x
    row_exact = (y - min_y) / pitch_y
    
    # Try rounding first
    col = col_exact.round
    row = row_exact.round
    
    # Check bounds
    if row >= 0 && row < rows && col >= 0 && col < cols
      # Only map if cell is empty
      if grid[row][col] == '.'
        # Calculate distance from wafer center
        dx = x - cx
        dy = y - cy
        dist = Math.sqrt(dx * dx + dy * dy)
        
        # Edge detection: dies within 3mm of edge
        if dist > (radius - 3.0)
          grid[row][col] = '*'
          edge_count += 1
        else
          grid[row][col] = '?'
        end
        
        mapped_count += 1
      else
        # Cell already occupied - this die might be a duplicate or misaligned
        skipped << [x, y]
      end
    else
      skipped << [x, y]
    end
  end
  
  puts "Mapped #{mapped_count} dies (#{edge_count} edge dies)"
  puts "Skipped: #{skipped.length} dies"
  
  # Second pass: try to map skipped dies to nearest empty cell
  if skipped.length > 0
    puts "Attempting to map #{skipped.length} skipped dies..."
    recovery_count = 0
    
    skipped.each do |pos|
      x = pos[0]
      y = pos[1]
      
      col_exact = (x - min_x) / pitch_x
      row_exact = (y - min_y) / pitch_y
      
      # Try neighboring cells
      base_col = col_exact.round
      base_row = row_exact.round
      
      found = false
      [-1, 0, 1].each do |dr|
        [-1, 0, 1].each do |dc|
          next if dr == 0 && dc == 0  # Already tried this
          
          col = base_col + dc
          row = base_row + dr
          
          if row >= 0 && row < rows && col >= 0 && col < cols && grid[row][col] == '.'
            dx = x - cx
            dy = y - cy
            dist = Math.sqrt(dx * dx + dy * dy)
            
            if dist > (radius - 3.0)
              grid[row][col] = '*'
            else
              grid[row][col] = '?'
            end
            
            recovery_count += 1
            found = true
            break
          end
        end
        break if found
      end
    end
    
    puts "Recovered #{recovery_count} additional dies"
  end
  
  return grid, pitch_x, pitch_y
end

# Write to file
def write_file(grid, pitch_x, pitch_y, output_path)
  return if grid.empty?
  
  puts "Writing to: #{output_path}"
  
  File.open(output_path, 'w') do |f|
    cols = grid[0].length
    rows = grid.length
    
    # Write header
    f.puts "\"PTVS\",#{cols},\"METRIC\",\"BOTTOM\",\"#{pitch_x.round(4)}\",\"#{pitch_y.round(4)}\",#{rows},#{cols},\"0\",\"0\""
    f.puts "\"44\",\"4\""
    f.puts "\"0\""
    f.puts "\"1\",\"4\""
    f.puts "\"POST\""
    f.puts "0\n0\n0\n\"FALSE\"\n0\n0\n\"FALSE\"\n\"0\"\n\"0\"\n\"7038\""
    f.puts "\"RVD\",\"RVD\",\"RVD\""
    f.puts "\"FALSE\"\n\"\"\n\"0\"\n\"100:6\""
    f.puts "\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\""
    f.puts "\"\"\n\"\""
    f.puts "\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\",\"RVD\""
    f.puts "\"25\""
    f.puts "\"1\",\"PASS\",\"\",\"0\",\"0\",\"PASS\",65280,\"0\",\"0\",\"False\""
    
    # Write grid (reversed for correct orientation)
    grid.reverse.each do |row|
      line = row.map { |cell| "\"#{cell}\"" }.join(',')
      f.puts line
    end
  end
  
  msg = "Success!\n\nFile: #{output_path}\nRows: #{grid.length}\nCols: #{grid[0].length}\nPitch: #{pitch_x.round(4)} x #{pitch_y.round(4)} mm"
  RBA::MessageBox.info("Done", msg, RBA::MessageBox::Ok)
  puts "DONE!"
end

# ===================== MAIN =====================
puts "=" * 60
puts "GDS to Wafer Map Converter (Ruby) - v9 Enhanced"
puts "=" * 60

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y = create_grid(positions, wafer_diameter_mm)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, pitch_x, pitch_y, output_path)
  end
end

puts "=" * 60
