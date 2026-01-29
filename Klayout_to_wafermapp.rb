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

# Calculate die pitch from actual positions
def calculate_pitch(positions)
  return [0, 0] if positions.length < 2
  
  # Sort positions
  sorted_x = positions.sort_by { |p| p[0] }
  sorted_y = positions.sort_by { |p| p[1] }
  
  # Find minimum spacing in X direction (must be > 0.5mm to avoid errors)
  x_spacings = []
  (0...sorted_x.length-1).each do |i|
    spacing = (sorted_x[i+1][0] - sorted_x[i][0]).abs
    x_spacings << spacing if spacing > 0.5  # Minimum 0.5mm spacing
  end
  
  # Find minimum spacing in Y direction
  y_spacings = []
  (0...sorted_y.length-1).each do |i|
    spacing = (sorted_y[i+1][1] - sorted_y[i][1]).abs
    y_spacings << spacing if spacing > 0.5  # Minimum 0.5mm spacing
  end
  
  # Use the most common small spacing as pitch
  pitch_x = x_spacings.empty? ? 1.1632 : x_spacings.min
  pitch_y = y_spacings.empty? ? 1.1632 : y_spacings.min
  
  puts "Calculated pitch - X: #{pitch_x.round(4)} mm, Y: #{pitch_y.round(4)} mm"
  
  return [pitch_x, pitch_y]
end

# Create grid with auto-calculated pitch
def create_grid(positions, wafer_diameter_mm)
  return [] if positions.empty?
  
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
  
  # Safety check: prevent huge grids
  if cols > 500 || rows > 500
    puts "ERROR: Grid too large! Cols: #{cols}, Rows: #{rows}"
    puts "Pitch might be too small. Check your die spacing."
    return [], pitch_x, pitch_y
  end
  
  puts "Grid: #{cols} cols x #{rows} rows"
  
  # Initialize grid with '.'
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
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
def write_file(grid, pitch_x, pitch_y, output_path)
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
  end
  
  msg = "Success!\n\nFile: #{output_path}\nRows: #{grid.length}\nCols: #{grid[0].length}\nPitch X: #{pitch_x.round(4)} mm\nPitch Y: #{pitch_y.round(4)} mm"
  RBA::MessageBox.info("Done", msg, RBA::MessageBox::Ok)
  puts "DONE!"
end

# ===================== MAIN =====================
puts "=" * 60
puts "GDS to Wafer Map Converter (Ruby)"
puts "=" * 60

output_path = "C:/temp/wafer_map.txt"
wafer_diameter_mm = 150.0
ep_layer = 18
ep_datatype = 0

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y = create_grid(positions, wafer_diameter_mm)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
    RBA::MessageBox.warning("Error", "Grid too large! Check the console for pitch values.", RBA::MessageBox::Ok)
  else
    write_file(grid, pitch_x, pitch_y, output_path)
  end
end

puts "=" * 60
