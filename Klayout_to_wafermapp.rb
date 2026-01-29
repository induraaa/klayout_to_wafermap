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

# Smart pitch calculation using sorted unique coordinates
def calculate_pitch_smart(positions)
  return [1.5, 1.5] if positions.length < 10
  
  # Get all unique X and Y coordinates (rounded to avoid floating point issues)
  x_coords = positions.map { |p| (p[0] * 100).round / 100.0 }.uniq.sort
  y_coords = positions.map { |p| (p[1] * 100).round / 100.0 }.uniq.sort
  
  puts "Unique X coordinates: #{x_coords.length}"
  puts "Unique Y coordinates: #{y_coords.length}"
  
  # Calculate differences between consecutive coordinates
  x_diffs = []
  (0...x_coords.length-1).each do |i|
    diff = x_coords[i+1] - x_coords[i]
    x_diffs << diff if diff > 0.1  # Ignore tiny differences
  end
  
  y_diffs = []
  (0...y_coords.length-1).each do |i|
    diff = y_coords[i+1] - y_coords[i]
    y_diffs << diff if diff > 0.1
  end
  
  # The pitch is the smallest common difference
  pitch_x = x_diffs.empty? ? 1.5 : x_diffs.min
  pitch_y = y_diffs.empty? ? 1.5 : y_diffs.min
  
  puts "Calculated pitch - X: #{pitch_x.round(4)} mm (from #{x_diffs.length} differences)"
  puts "Calculated pitch - Y: #{pitch_y.round(4)} mm (from #{y_diffs.length} differences)"
  
  return [pitch_x, pitch_y]
end

# Create grid
def create_grid(positions, wafer_diameter_mm)
  return [], 0, 0 if positions.empty?
  
  # Calculate pitch from positions
  pitch_x, pitch_y = calculate_pitch_smart(positions)
  
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
    puts "WARNING: Grid is very large (#{cols}x#{rows})!"
    puts "This might indicate incorrect pitch calculation."
  end
  
  # Initialize grid with '.'
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  puts "Wafer center: (#{cx.round(2)}, #{cy.round(2)})"
  puts "Mapping #{positions.length} dies to grid..."
  
  mapped_count = 0
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
      mapped_count += 1
    end
  end
  
  puts "Successfully mapped #{mapped_count} / #{positions.length} dies"
  
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
