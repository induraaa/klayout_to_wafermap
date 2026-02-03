# CONFIGURATION - CHANGE THESE!
output_path = "C:/temp/wafer_map.txt"
wafer_diameter_mm = 150.0
ep_layer = 18
ep_datatype = 0

# MANUAL PITCH OVERRIDE
PITCH_X_MM = 1.467
PITCH_Y_MM = 1.467
TOLERANCE_FACTOR = 0.75  # 75% of pitch

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
  
  # Filter out test structures (anything > 2x median size)
  sorted_sizes = sizes.sort
  median_size = sorted_sizes[sorted_sizes.length / 2]
  
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

# Create grid with two-pass mapping
def create_grid(positions, wafer_diameter_mm, pitch_x, pitch_y, tolerance_factor)
  return [], 0, 0, 0, 0 if positions.empty?
  
  x_list = positions.map { |p| p[0] }
  y_list = positions.map { |p| p[1] }
  
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max
  
  puts "X range: #{min_x.round(3)} to #{max_x.round(3)} mm"
  puts "Y range: #{min_y.round(3)} to #{max_y.round(3)} mm"
  puts "Using pitch - X: #{pitch_x} mm, Y: #{pitch_y} mm"
  puts "Tolerance: #{(tolerance_factor * 100).round(1)}% of pitch"
  
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
  
  # PASS 1: Map dies with normal tolerance
  mapped_count = 0
  edge_count = 0
  tolerance = [pitch_x, pitch_y].max * tolerance_factor
  
  puts "PASS 1: Mapping with tolerance #{tolerance.round(4)} mm..."
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
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
        
        cell_x = min_x + test_col * pitch_x
        cell_y = min_y + test_row * pitch_y
        dist = Math.sqrt((x - cell_x)**2 + (y - cell_y)**2)
        
        if dist < min_dist && dist < tolerance
          min_dist = dist
          best_col = test_col
          best_row = test_row
        end
      end
    end
    
    if best_col && best_row && grid[best_row][best_col] == '.'
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
    end
  end
  
  puts "PASS 1: Mapped #{mapped_count} / #{positions.length} dies"
  
  # PASS 2: Force map remaining dies to nearest empty cell
  puts "PASS 2: Forcing unmapped dies..."
  second_pass = 0
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    col_exact = (x - min_x) / pitch_x
    row_exact = (y - min_y) / pitch_y
    
    col_center = col_exact.round
    row_center = row_exact.round
    
    # Check if this die was already mapped in first pass
    already_mapped = false
    
    (-1..1).each do |dr|
      (-1..1).each do |dc|
        test_col = col_center + dc
        test_row = row_center + dr
        
        next if test_col < 0 || test_col >= cols
        next if test_row < 0 || test_row >= rows
        
        if grid[test_row][test_col] != '.'
          # Check if this cell is close to our die
          cell_x = min_x + test_col * pitch_x
          cell_y = min_y + test_row * pitch_y
          dist = Math.sqrt((x - cell_x)**2 + (y - cell_y)**2)
          
          if dist < tolerance
            already_mapped = true
            break
          end
        end
      end
      break if already_mapped
    end
    
    next if already_mapped
    
    # Not mapped! Find nearest empty cell within 5x5 grid
    best_col = nil
    best_row = nil
    min_dist = Float::INFINITY
    
    (-2..2).each do |dr|
      (-2..2).each do |dc|
        test_col = col_center + dc
        test_row = row_center + dr
        
        next if test_col < 0 || test_col >= cols
        next if test_row < 0 || test_row >= rows
        next if grid[test_row][test_col] != '.'  # Must be empty
        
        cell_x = min_x + test_col * pitch_x
        cell_y = min_y + test_row * pitch_y
        dist = Math.sqrt((x - cell_x)**2 + (y - cell_y)**2)
        
        if dist < min_dist
          min_dist = dist
          best_col = test_col
          best_row = test_row
        end
      end
    end
    
    if best_col && best_row
      dx = x - cx
      dy = y - cy
      wafer_dist = Math.sqrt(dx * dx + dy * dy)
      
      if wafer_dist > (radius - 3.0)
        grid[best_row][best_col] = '*'
      else
        grid[best_row][best_col] = '?'
      end
      
      second_pass += 1
    end
  end
  
  puts "PASS 2: Recovered #{second_pass} additional dies"
  mapped_count += second_pass
  
  # Count remaining dots in wafer area
  dot_count = 0
  grid.each_with_index do |row, r|
    row.each_with_index do |cell, c|
      if cell == '.'
        x = min_x + c * pitch_x
        y = min_y + r * pitch_y
        dx = x - cx
        dy = y - cy
        dist = Math.sqrt(dx * dx + dy * dy)
        
        if dist <= radius
          dot_count += 1
        end
      end
    end
  end
  
  puts "Total mapped: #{mapped_count} / #{positions.length} dies (#{edge_count} edge)"
  puts "Unmapped: #{positions.length - mapped_count} dies"
  puts "Empty cells inside wafer: #{dot_count}"
  
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
puts "GDS to Wafer Map Converter - TWO-PASS MAPPING"
puts "=" * 60

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y, mapped_count, dot_count = create_grid(positions, wafer_diameter_mm, PITCH_X_MM, PITCH_Y_MM, TOLERANCE_FACTOR)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, pitch_x, pitch_y, output_path, positions.length, mapped_count, dot_count)
  end
end

puts "=" * 60
