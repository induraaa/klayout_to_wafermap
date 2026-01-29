# CONFIGURATION - CHANGE THESE!
output_path = "C:/temp/wafer_map.txt"
die_size_x_mm = 1.5
die_size_y_mm = 1.5
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
  
  puts "Processing layout..."
  puts "Cell: #{cell.basic_name}"
  
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
def calculate_die_pitch(positions)
  return nil, nil if positions.length < 2
  
  x_list = positions.map { |p| p[0] }.sort
  y_list = positions.map { |p| p[1] }.sort
  
  # Calculate minimum spacing in X direction
  x_spacings = []
  (1...x_list.length).each do |i|
    spacing = x_list[i] - x_list[i-1]
    x_spacings << spacing if spacing > 0.01  # Ignore very small differences (noise)
  end
  
  # Calculate minimum spacing in Y direction
  y_spacings = []
  (1...y_list.length).each do |i|
    spacing = y_list[i] - y_list[i-1]
    y_spacings << spacing if spacing > 0.01  # Ignore very small differences (noise)
  end
  
  pitch_x = x_spacings.empty? ? nil : x_spacings.min
  pitch_y = y_spacings.empty? ? nil : y_spacings.min
  
  return pitch_x, pitch_y
end

# Create grid
def create_grid(positions, die_size_x_mm, die_size_y_mm, wafer_diameter_mm)
  return [], nil, nil if positions.empty?
  
  x_list = positions.map { |p| p[0] }
  y_list = positions.map { |p| p[1] }
  
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max
  
  puts "X range: #{min_x.round(3)} to #{max_x.round(3)} mm"
  puts "Y range: #{min_y.round(3)} to #{max_y.round(3)} mm"
  
  # Auto-calculate die pitch from actual positions
  pitch_x, pitch_y = calculate_die_pitch(positions)
  
  if pitch_x.nil? || pitch_y.nil?
    puts "WARNING: Could not calculate pitch, using manual die size"
    pitch_x = die_size_x_mm
    pitch_y = die_size_y_mm
  else
    puts "Calculated pitch: X=#{pitch_x.round(4)} mm, Y=#{pitch_y.round(4)} mm"
    puts "Manual die size: X=#{die_size_x_mm} mm, Y=#{die_size_y_mm} mm"
  end
  
  cols = ((max_x - min_x) / pitch_x).round + 1
  rows = ((max_y - min_y) / pitch_y).round + 1
  
  puts "Grid: #{cols} cols x #{rows} rows"
  puts "Expected dies: #{positions.length}"
  
  # Initialize grid with '.'
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  placed_dies = 0
  edge_dies = 0
  good_dies = 0
  
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
        edge_dies += 1
      else
        grid[row][col] = '?'
        good_dies += 1
      end
      placed_dies += 1
    end
  end
  
  puts "Placed dies: #{placed_dies} (#{good_dies} good, #{edge_dies} edge)"
  
  return grid, pitch_x, pitch_y
end

# Write to file
def write_file(grid, output_path, pitch_x, pitch_y)
  return if grid.empty?
  
  puts "Writing to: #{output_path}"
  
  File.open(output_path, 'w') do |f|
    cols = grid[0].length
    rows = grid.length
    
    # Write header with calculated pitch
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
  
  msg = "Success!\n\nFile: #{output_path}\nRows: #{grid.length}\nCols: #{grid[0].length}"
  RBA::MessageBox.info("Done", msg, RBA::MessageBox::Ok)
  puts "DONE!"
end

# ===================== MAIN =====================
puts "=" * 60
puts "GDS to Wafer Map Converter (Ruby)"
puts "=" * 60

output_path = "C:/temp/wafer_map.txt"  # CHANGE THIS!
die_size_x_mm = 1.1632
die_size_y_mm = 1.1632
wafer_diameter_mm = 150.0
ep_layer = 18
ep_datatype = 0

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y = create_grid(positions, die_size_x_mm, die_size_y_mm, wafer_diameter_mm)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, output_path, pitch_x, pitch_y)
  end
end

puts "=" * 60
