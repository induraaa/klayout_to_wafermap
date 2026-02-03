# CONFIGURATION - CHANGE THESE!
output_path = "C:/temp/wafer_map.txt"
wafer_diameter_mm = 150.0
ep_layer = 18
ep_datatype = 0

# MANUAL PITCH OVERRIDE (calculated from your data)
PITCH_X_MM = 1.785
PITCH_Y_MM = 1.81

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

# Extract die positions and sizes
def extract_die_positions(ep_layer, ep_datatype)
  layout, cell = get_current_layout
  return [] if layout.nil?
  
  layer_idx = layout.layer(ep_layer, ep_datatype)
  shapes = cell.shapes(layer_idx)
  
  positions = []
  sizes = []
  count = 0
  
  shapes.each do |shape|
    count += 1
    bbox = shape.bbox
    
    cx = (bbox.left + bbox.right) / 2.0
    cy = (bbox.bottom + bbox.top) / 2.0
    
    cx_mm = cx * layout.dbu / 1000.0
    cy_mm = cy * layout.dbu / 1000.0
    
    width_mm = (bbox.right - bbox.left) * layout.dbu / 1000.0
    height_mm = (bbox.top - bbox.bottom) * layout.dbu / 1000.0
    area_mm2 = width_mm * height_mm
    
    positions << [cx_mm, cy_mm]
    sizes << area_mm2
  end
  
  puts "Found shapes: #{count}"
  puts "Die positions: #{positions.length}"
  
  # Calculate median size to identify normal dies
  sorted_sizes = sizes.sort
  median_size = sorted_sizes[sorted_sizes.length / 2]
  
  # Filter out test structures (anything > 2x median size)
  normal_dies = []
  test_structures = []
  
  positions.each_with_index do |pos, i|
    if sizes[i] > median_size * 2.0
      test_structures << pos
      puts "Test structure at (#{pos[0].round(2)}, #{pos[1].round(2)}) - size: #{sizes[i].round(2)} mm²"
    else
      normal_dies << pos
    end
  end
  
  puts "Normal dies: #{normal_dies.length}"
  puts "Test structures: #{test_structures.length}"
  
  return normal_dies
end

# Create grid with flexible tolerance
def create_grid(positions, wafer_diameter_mm, pitch_x, pitch_y)
  return [], 0, 0, 0, 0 if positions.empty?
  
  x_list = positions.map { |p| p[0] }
  y_list = positions.map { |p| p[1] }
  
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max
  
  puts "X range: #{min_x.round(3)} to #{max_x.round(3)} mm"
  puts "Y range: #{min_y.round(3)} to #{max_y.round(3)} mm"
  puts "Using MANUAL pitch - X: #{pitch_x} mm, Y: #{pitch_y} mm"
  
  cols = ((max_x - min_x) / pitch_x).round + 1
  rows = ((max_y - min_y) / pitch_y).round + 1
  
  puts "Grid: #{cols} cols x #{rows} rows"
  
  # Initialize grid with '.'
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  # Wafer center calculation
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  puts "Wafer center: (#{cx.round(2)}, #{cy.round(2)}) mm"
  puts "Radius: #{radius} mm"
  
  # Map EVERY die to the closest grid cell within search radius
  mapped_count = 0
  edge_count = 0
  unmapped = []
  
  tolerance = [pitch_x, pitch_y].max * 0.6  # Search within 60% of pitch
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    # Find closest grid cell
    col_exact = (x - min_x) / pitch_x
    row_exact = (y - min_y) / pitch_y
    
    col_center = col_exact.round
    row_center = row_exact.round
    
    # Search 3x3 neighborhood for best empty cell
    best_col = nil
    best_row = nil
    min_dist = Float::INFINITY
    
    (-1..1).each do |dr|
      (-1..1).each do |dc|
        test_col = col_center + dc
        test_row = row_center + dr
        
        next if test_col < 0 || test_col >= cols
        next if test_row < 0 || test_row >= rows
        
        # Calculate distance from die to this cell center
        cell_x = min_x + test_col * pitch_x
        cell_y = min_y + test_row * pitch_y
        dist = Math.sqrt((x - cell_x)**2 + (y - cell_y)**2)
        
        # Accept if closer and within tolerance
        if dist < min_dist && dist < tolerance
          min_dist = dist
          best_col = test_col
          best_row = test_row
        end
      end
    end
    
    # Map to best cell
    if best_col && best_row
      # Only fill if empty (don't overwrite)
      if grid[best_row][best_col] == '.'
        # Calculate distance from wafer center
        dx = x - cx
        dy = y - cy
        wafer_dist = Math.sqrt(dx * dx + dy * dy)
        
        if wafer_dist > (radius - 3.0)
          grid[best_row][best_col] = '*'
          edge_count += 1
        else
          grid[best_row][best_col] = '?'
        end
        
        mapped_count += 1
      else
        # Cell already occupied - collision
        unmapped << [x, y, "collision"]
      end
    else
      # No suitable cell found
      unmapped << [x, y, "out of tolerance"]
    end
  end
  
  # Count remaining dots in wafer area
  dot_count = 0
  grid.each_with_index do |row, r|
    row.each_with_index do |cell, c|
      if cell == '.'
        # Calculate position of this cell
        x = min_x + c * pitch_x
        y = min_y + r * pitch_y
        dx = x - cx
        dy = y - cy
        dist = Math.sqrt(dx * dx + dy * dy)
        
        # Only count dots inside wafer radius
        if dist <= radius
          dot_count += 1
        end
      end
    end
  end
  
  puts "Mapped: #{mapped_count} / #{positions.length} dies (#{edge_count} edge)"
  puts "Unmapped: #{unmapped.length} dies"
  puts "Empty cells inside wafer: #{dot_count}"
  
  if unmapped.length > 0 && unmapped.length < 20
    puts "Unmapped die details:"
    unmapped.each do |u|
      puts "  (#{u[0].round(2)}, #{u[1].round(2)}) - #{u[2]}"
    end
  end
  
  return grid, pitch_x, pitch_y, mapped_count, dot_count
end

# Write to file
def write_file(grid, pitch_x, pitch_y, output_path, total_dies, mapped_count, dot_count)
  return if grid.empty?
  
  puts "Writing to: #{output_path}"
  
  File.open(output_path, 'w') do |f|
    cols = grid[0].length
    rows = grid.length
    
    # Write header
    f.puts "\"PTVS\",#{cols},\"METRIC\",\"BOTTOM\",\"#{pitch_x}\",\"#{pitch_y}\",#{rows},#{cols},\"0\",\"0\""
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
    
    # Write statistics as comments at the end
    f.puts ""
    f.puts "# ===== MAPPING STATISTICS ====="
    f.puts "# Total dies in GDS: #{total_dies}"
    f.puts "# Mapped to grid: #{mapped_count}"
    f.puts "# Unmapped dies: #{total_dies - mapped_count}"
    f.puts "# Empty cells (dots) inside wafer: #{dot_count}"
    f.puts "# Grid size: #{cols} x #{rows}"
    f.puts "# Pitch: #{pitch_x} x #{pitch_y} mm"
    f.puts "# Mapping success rate: #{((mapped_count.to_f / total_dies) * 100).round(2)}%"
    f.puts "# ==============================="
  end
  
  msg = "Success!\n\nFile: #{output_path}\nRows: #{grid.length}\nCols: #{grid[0].length}\nMapped: #{mapped_count}/#{total_dies} (#{((mapped_count.to_f / total_dies) * 100).round(1)}%)\nDots inside wafer: #{dot_count}"
  RBA::MessageBox.info("Done", msg, RBA::MessageBox::Ok)
  puts "DONE!"
end

# ===================== MAIN =====================
puts "=" * 60
puts "GDS to Wafer Map Converter - v10 TOLERANCE MAPPING"
puts "=" * 60

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y, mapped_count, dot_count = create_grid(positions, wafer_diameter_mm, PITCH_X_MM, PITCH_Y_MM)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, pitch_x, pitch_y, output_path, positions.length, mapped_count, dot_count)
  end
end

puts "=" * 60
