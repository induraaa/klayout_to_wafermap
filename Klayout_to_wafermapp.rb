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
  
  # Filter out test structures
  sorted_sizes = sizes.sort
  median_size = sorted_sizes[sorted_sizes.length / 2]
  
  normal_dies = []
  positions.each_with_index do |pos, i|
    if sizes[i] <= median_size * 2.0
      normal_dies << pos
    end
  end
  
  puts "Normal dies: #{normal_dies.length}"
  
  return normal_dies
end

# Calculate EXACT pitch by analyzing actual nearest neighbor distances
def calculate_exact_pitch(positions, sample_size = 500)
  return [1.466, 1.466] if positions.length < 100
  
  sample = positions.take([sample_size, positions.length].min)
  
  x_distances = []
  y_distances = []
  
  sample.each_with_index do |pos, i|
    nearest_x = Float::INFINITY
    nearest_y = Float::INFINITY
    
    positions.each_with_index do |other, j|
      next if i == j
      
      dx = (other[0] - pos[0]).abs
      dy = (other[1] - pos[1]).abs
      
      # Find nearest in X (same row: Y within 0.5mm)
      if dy < 0.5 && dx > 0.1 && dx < 3.0
        nearest_x = dx if dx < nearest_x
      end
      
      # Find nearest in Y (same column: X within 0.5mm)
      if dx < 0.5 && dy > 0.1 && dy < 3.0
        nearest_y = dy if dy < nearest_y
      end
    end
    
    x_distances << nearest_x if nearest_x < Float::INFINITY
    y_distances << nearest_y if nearest_y < Float::INFINITY
  end
  
  # Use MODE (most common value) instead of median
  pitch_x = mode_of_distances(x_distances)
  pitch_y = mode_of_distances(y_distances)
  
  puts "Calculated pitch from die spacing:"
  puts "  X: #{pitch_x.round(4)} mm (from #{x_distances.length} samples)"
  puts "  Y: #{pitch_y.round(4)} mm (from #{y_distances.length} samples)"
  
  return [pitch_x, pitch_y]
end

# Find mode (most common value) by binning
def mode_of_distances(distances)
  return 1.466 if distances.empty?
  
  # Create histogram with 0.001mm bins
  histogram = Hash.new(0)
  
  distances.each do |d|
    bin = (d * 1000).round  # Convert to 0.001mm bins
    histogram[bin] += 1
  end
  
  # Find most common bin
  max_count = histogram.values.max
  mode_bin = histogram.key(max_count)
  
  mode_value = mode_bin / 1000.0
  
  return mode_value
end

# Create grid with calculated pitch
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
  puts "Using pitch - X: #{pitch_x} mm, Y: #{pitch_y} mm"
  
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
  
  # Map each die - use EXPANDED tolerance
  mapped_count = 0
  edge_count = 0
  tolerance = [pitch_x, pitch_y].max * 0.7  # 70% of pitch
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    col_exact = (x - min_x) / pitch_x
    row_exact = (y - min_y) / pitch_y
    
    col_center = col_exact.round
    row_center = row_exact.round
    
    # Search 3x3 for best cell
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
  
  # Count dots
  dot_count = 0
  grid.each_with_index do |row, r|
    row.each_with_index do |cell, c|
      if cell == '.'
        x = min_x + c * pitch_x
        y = min_y + r * pitch_y
        dx = x - cx
        dy = y - cy
        dist = Math.sqrt(dx * dx + dy * dy)
        dot_count += 1 if dist <= radius
      end
    end
  end
  
  puts "Mapped: #{mapped_count} / #{positions.length} dies"
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
    
    # Write grid
    grid.reverse.each do |row|
      line = row.map { |cell| "\"#{cell}\"" }.join(',')
      f.puts line
    end
    
    # Statistics
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
  
  msg = "Success!\n\nMapped: #{mapped_count}/#{total_dies} (#{((mapped_count.to_f / total_dies) * 100).round(1)}%)\nDots inside wafer: #{dot_count}"
  RBA::MessageBox.info("Done", msg, RBA::MessageBox::Ok)
  puts "DONE!"
end

# ===================== MAIN =====================
puts "=" * 60
puts "GDS to Wafer Map - ADAPTIVE PITCH CALCULATION"
puts "=" * 60

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found!", RBA::MessageBox::Ok)
else
  # Calculate pitch from actual die spacing
  pitch_x, pitch_y = calculate_exact_pitch(positions)
  
  grid, pitch_x, pitch_y, mapped_count, dot_count = create_grid(positions, wafer_diameter_mm, pitch_x, pitch_y)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, pitch_x, pitch_y, output_path, positions.length, mapped_count, dot_count)
  end
end

puts "=" * 60
