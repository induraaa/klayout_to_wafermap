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

# Find unique row and column positions by clustering
def find_grid_lines(positions)
  x_coords = positions.map { |p| p[0] }.sort
  y_coords = positions.map { |p| p[1] }.sort
  
  # Cluster X coordinates (find unique columns)
  x_clusters = cluster_coordinates(x_coords, 0.5)  # 0.5mm tolerance
  y_clusters = cluster_coordinates(y_coords, 0.5)
  
  puts "Found #{x_clusters.length} unique columns"
  puts "Found #{y_clusters.length} unique rows"
  
  return x_clusters, y_clusters
end

# Cluster nearby coordinates together
def cluster_coordinates(coords, tolerance)
  return [] if coords.empty?
  
  clusters = []
  current_cluster = [coords[0]]
  
  (1...coords.length).each do |i|
    if (coords[i] - current_cluster.last).abs <= tolerance
      current_cluster << coords[i]
    else
      # Finalize cluster (use median)
      clusters << median(current_cluster)
      current_cluster = [coords[i]]
    end
  end
  
  # Don't forget last cluster
  clusters << median(current_cluster) if !current_cluster.empty?
  
  return clusters
end

# Create grid based on ACTUAL die positions
def create_grid_from_actual_positions(positions, wafer_diameter_mm)
  return [] if positions.empty?
  
  # Find actual grid lines from die positions
  x_grid, y_grid = find_grid_lines(positions)
  
  cols = x_grid.length
  rows = y_grid.length
  
  puts "Grid: #{cols} cols x #{rows} rows (from actual positions)"
  
  # Safety check
  if cols > 300 || rows > 300
    puts "ERROR: Grid too large!"
    return [], 0, 0
  end
  
  # Initialize grid
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  # Calculate wafer center
  min_x = x_grid.min
  max_x = x_grid.max
  min_y = y_grid.min
  max_y = y_grid.max
  
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  puts "Wafer center: (#{cx.round(2)}, #{cy.round(2)}) mm"
  
  # Calculate average pitch for header
  pitch_x = cols > 1 ? (max_x - min_x) / (cols - 1) : 1.78
  pitch_y = rows > 1 ? (max_y - min_y) / (rows - 1) : 1.81
  
  puts "Average pitch - X: #{pitch_x.round(4)} mm, Y: #{pitch_y.round(4)} mm"
  
  # Map each die to nearest grid intersection
  mapped_count = 0
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    # Find nearest column
    col = find_nearest_index(x, x_grid)
    row = find_nearest_index(y, y_grid)
    
    if row >= 0 && row < rows && col >= 0 && col < cols
      # Calculate distance from wafer center
      dx = x - cx
      dy = y - cy
      dist = Math.sqrt(dx * dx + dy * dy)
      
      # Only set if empty
      if grid[row][col] == '.'
        if dist > (radius - 3.0)
          grid[row][col] = '*'
        else
          grid[row][col] = '?'
        end
        mapped_count += 1
      end
    end
  end
  
  puts "Mapped #{mapped_count} / #{positions.length} dies"
  
  return grid, pitch_x, pitch_y
end

# Find index of nearest value in sorted array
def find_nearest_index(value, array)
  return 0 if array.empty?
  
  min_diff = Float::INFINITY
  best_idx = 0
  
  array.each_with_index do |grid_val, idx|
    diff = (value - grid_val).abs
    if diff < min_diff
      min_diff = diff
      best_idx = idx
    end
  end
  
  return best_idx
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
puts "GDS to Wafer Map Converter - CLUSTERING APPROACH"
puts "=" * 60

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y = create_grid_from_actual_positions(positions, wafer_diameter_mm)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, pitch_x, pitch_y, output_path)
  end
end

puts "=" * 60
