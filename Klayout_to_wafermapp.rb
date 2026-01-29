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

def median(array)
  return 0 if array.empty?
  sorted = array.sort
  len = sorted.length
  (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
end

# Calculate die pitch by finding nearest neighbor distances
def calculate_pitch(positions)
  return [1.8, 1.8] if positions.length < 10
  
  # Sample first 100 dies to find nearest neighbor distances
  sample_size = [100, positions.length].min
  nearest_distances_x = []
  nearest_distances_y = []
  
  (0...sample_size).each do |i|
    pos = positions[i]
    
    # Find nearest neighbor in X direction (same Y approximately)
    nearest_x = nil
    positions.each do |other|
      next if pos == other
      dy = (other[1] - pos[1]).abs
      next if dy > 0.5  # Must be in same row
      
      dx = (other[0] - pos[0]).abs
      if dx > 0.5 && (nearest_x.nil? || dx < nearest_x)
        nearest_x = dx
      end
    end
    nearest_distances_x << nearest_x if nearest_x
    
    # Find nearest neighbor in Y direction (same X approximately)
    nearest_y = nil
    positions.each do |other|
      next if pos == other
      dx = (other[0] - pos[0]).abs
      next if dx > 0.5  # Must be in same column
      
      dy = (other[1] - pos[1]).abs
      if dy > 0.5 && (nearest_y.nil? || dy < nearest_y)
        nearest_y = dy
      end
    end
    nearest_distances_y << nearest_y if nearest_y
  end
  
  # Use median of nearest distances as pitch
  pitch_x = nearest_distances_x.empty? ? 1.8 : median(nearest_distances_x)
  pitch_y = nearest_distances_y.empty? ? 1.8 : median(nearest_distances_y)
  
  puts "Calculated pitch - X: #{pitch_x.round(4)} mm, Y: #{pitch_y.round(4)} mm"
  puts "Sample sizes - X: #{nearest_distances_x.length}, Y: #{nearest_distances_y.length}"
  
  return [pitch_x, pitch_y]
end

# Create grid
def create_grid(positions, wafer_diameter_mm)
  return [], 0, 0 if positions.empty?
  
  # Calculate pitch from positions
  pitch_x, pitch_y = calculate_pitch(positions)
  
  x_list = positions.map { |p| p[0] }
  y_list = positions.map { |p| p[1] }
  
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max
  
  puts "X range: #{min_x.round(3)} to #{max_x.round(3)}"
  puts "Y range: #{min_y.round(3)} to #{max_y.round(3)}"
  
  cols = ((max_x - min_x) / pitch_x).round + 1
  rows = ((max_y - min_y) / pitch_y).round + 1
  
  puts "Grid: #{cols} cols x #{rows} rows"
  
  # Safety check
  if cols > 200 || rows > 200
    puts "WARNING: Grid is large (#{cols}x#{rows}). This might take a while..."
  end
  
  # Initialize grid with '.'
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  puts "Wafer center: (#{cx.round(2)}, #{cy.round(2)})"
  puts "Mapping #{positions.length} dies to grid..."
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    col = ((x - min_x) / pitch_x).round
    row = ((y - min_y) / pitch_y).round
    
    if row >= 0 && row < rows && col >= 0 && col < cols
      dx = x - cx
      dy = y - cy
      dist = Math.sqrt(dx * dx + dy * dy)
      
      if dist > radius * 0.95
        grid[row][col] = '*'
      else
        grid[row][col] = '?'
      end
    end
  end
  
  return grid, pitch_x, pitch_y
end

# Write to file
def write_file(grid, pitch_x, pitch_y, output_path, num_dies)
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
  
  msg = "Success!\n\nFile: #{output_path}\nRows: #{grid.length}\nCols: #{grid[0].length}\nPitch: #{pitch_x.round(4)} x #{pitch_y.round(4)} mm\nDies mapped: #{num_dies}"
  RBA::MessageBox.info("Done", msg, RBA::MessageBox::Ok)
  puts "DONE!"
end

# ===================== MAIN =====================
puts "=" * 60
puts "GDS to Wafer Map Converter (Ruby)"
puts "=" * 60

die_positions = extract_die_positions(ep_layer, ep_datatype)

if die_positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  result_grid, result_pitch_x, result_pitch_y = create_grid(die_positions, wafer_diameter_mm)
  
  if result_grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(result_grid, result_pitch_x, result_pitch_y, output_path, die_positions.length)
  end
end

puts "=" * 60
