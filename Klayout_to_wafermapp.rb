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

# Simple 1D K-Means clustering for coordinate values
def kmeans_1d(values, expected_pitch, tolerance = 0.3)
  return [] if values.empty?
  
  sorted = values.sort
  min_val = sorted.first
  max_val = sorted.last
  
  # Estimate number of clusters based on range and pitch
  num_clusters = ((max_val - min_val) / expected_pitch).round + 1
  
  puts "  Attempting #{num_clusters} clusters for range #{min_val.round(2)} to #{max_val.round(2)}"
  
  # Initialize cluster centers evenly
  centers = []
  (0...num_clusters).each do |i|
    centers << min_val + i * expected_pitch
  end
  
  # Run k-means iterations
  10.times do |iteration|
    # Assign each value to nearest center
    assignments = Array.new(num_clusters) { [] }
    
    sorted.each do |val|
      nearest_idx = 0
      min_dist = (val - centers[0]).abs
      
      (1...num_clusters).each do |i|
        dist = (val - centers[i]).abs
        if dist < min_dist
          min_dist = dist
          nearest_idx = i
        end
      end
      
      assignments[nearest_idx] << val
    end
    
    # Update centers to mean of assigned values
    new_centers = []
    assignments.each_with_index do |cluster, i|
      if cluster.empty?
        new_centers << centers[i]  # Keep old center if no assignments
      else
        new_centers << (cluster.sum / cluster.length.to_f)
      end
    end
    
    # Check convergence
    max_change = 0
    (0...num_clusters).each do |i|
      change = (new_centers[i] - centers[i]).abs
      max_change = change if change > max_change
    end
    
    centers = new_centers
    
    break if max_change < 0.01  # Converged
  end
  
  # Remove empty clusters and sort
  final_centers = centers.select do |center|
    sorted.any? { |val| (val - center).abs < tolerance }
  end
  
  return final_centers.sort
end

# Create grid using k-means clustering
def create_grid_kmeans(positions, wafer_diameter_mm)
  return [] if positions.empty?
  
  x_list = positions.map { |p| p[0] }
  y_list = positions.map { |p| p[1] }
  
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max
  
  puts "X range: #{min_x.round(3)} to #{max_x.round(3)} mm"
  puts "Y range: #{min_y.round(3)} to #{max_y.round(3)} mm"
  
  # Estimate pitch from range and expected die count
  estimated_cols = Math.sqrt(positions.length * (max_x - min_x) / (max_y - min_y)).round
  estimated_rows = Math.sqrt(positions.length * (max_y - min_y) / (max_x - min_x)).round
  
  pitch_x_estimate = (max_x - min_x) / (estimated_cols - 1)
  pitch_y_estimate = (max_y - min_y) / (estimated_rows - 1)
  
  puts "Estimated pitch - X: #{pitch_x_estimate.round(4)} mm, Y: #{pitch_y_estimate.round(4)} mm"
  
  # Run k-means to find grid line positions
  puts "K-means clustering X coordinates..."
  x_grid = kmeans_1d(x_list, pitch_x_estimate, 0.5)
  
  puts "K-means clustering Y coordinates..."
  y_grid = kmeans_1d(y_list, pitch_y_estimate, 0.5)
  
  cols = x_grid.length
  rows = y_grid.length
  
  puts "Grid: #{cols} cols x #{rows} rows"
  
  # Safety check
  if cols > 300 || rows > 300 || cols < 10 || rows < 10
    puts "ERROR: Grid size unusual (#{cols}x#{rows})"
    return [], 0, 0
  end
  
  # Initialize grid
  grid = Array.new(rows) { Array.new(cols, '.') }
  
  # Calculate wafer center
  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0
  
  puts "Wafer center: (#{cx.round(2)}, #{cy.round(2)}) mm"
  
  # Calculate average pitch for header
  pitch_x = cols > 1 ? (x_grid.last - x_grid.first) / (cols - 1) : pitch_x_estimate
  pitch_y = rows > 1 ? (y_grid.last - y_grid.first) / (rows - 1) : pitch_y_estimate
  
  puts "Final pitch - X: #{pitch_x.round(4)} mm, Y: #{pitch_y.round(4)} mm"
  
  # Map each die to nearest grid cell
  mapped_count = 0
  
  positions.each do |pos|
    x = pos[0]
    y = pos[1]
    
    # Find nearest column
    col = find_nearest_index(x, x_grid)
    row = find_nearest_index(y, y_grid)
    
    # Check distance to grid intersection
    if col && row
      grid_x = x_grid[col]
      grid_y = y_grid[row]
      
      snap_dist = Math.sqrt((x - grid_x)**2 + (y - grid_y)**2)
      
      # Only map if close enough (within 0.6mm)
      if snap_dist < 0.6 && grid[row][col] == '.'
        # Calculate distance from wafer center
        dx = x - cx
        dy = y - cy
        dist = Math.sqrt(dx * dx + dy * dy)
        
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

# Find index of nearest value in array
def find_nearest_index(value, array)
  return nil if array.empty?
  
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
puts "GDS to Wafer Map Converter - K-MEANS CLUSTERING"
puts "=" * 60

positions = extract_die_positions(ep_layer, ep_datatype)

if positions.empty?
  RBA::MessageBox.warning("Error", "No die found! Check layer 18/0", RBA::MessageBox::Ok)
else
  grid, pitch_x, pitch_y = create_grid_kmeans(positions, wafer_diameter_mm)
  
  if grid.empty?
    puts "ERROR: Could not create grid"
  else
    write_file(grid, pitch_x, pitch_y, output_path)
  end
end

puts "=" * 60
