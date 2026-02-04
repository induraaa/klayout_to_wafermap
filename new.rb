#
# Klayout wafer mapper with automatic rotation correction (PCA) + adaptive pitch
# Run inside KLayout (Macro -> Run Script)
#
# Outputs a PTVS wafer map text file with much better alignment for rotated/diamond lattices.
#
# CONFIGURE: output_path, layer/datatype, wafer diameter, sampling sizes
#
include RBA
require 'matrix'

# ---------- CONFIG ----------
OUTPUT_PATH = "C:/temp/wafer_map_rotated.txt"
SHAPE_LAYER = 18
SHAPE_DATATYPE = 0
EXPORT_IN_MM = true
WAFER_DIAMETER_MM = 150.0

# Nearest-neighbor sample size for pitch estimation (1k is usually fine)
NN_SAMPLE = 800

# Tolerance factors
INITIAL_TOLERANCE_FACTOR = 0.75   # used during first mapping pass (fraction of pitch)
FORCE_SEARCH_RADIUS = 4          # search radius (in cells) for second/pass forcing

# Test-structure detection: anything larger than TEST_SIZE_FACTOR * median area will be excluded
TEST_SIZE_FACTOR = 2.0

# -----------------------------

def get_active_layout_and_cell
  lv = RBA::LayoutView.current
  raise "No active LayoutView - open layout and click inside it before running." if lv.nil?
  cv = lv.active_cellview
  raise "No active cellview/layout." if cv.nil? || cv.layout.nil?
  return cv.layout, cv.cell
end

def extract_shape_centers(layout, top_cell, layer, datatype, export_in_mm)
  scale = export_in_mm ? (layout.dbu / 1000.0) : layout.dbu
  layer_idx = layout.layer(layer, datatype)
  shapes = top_cell.shapes(layer_idx)

  positions = []
  areas = []
  shapes.each do |shape|
    bbox = shape.bbox
    cx = (bbox.left + bbox.right) / 2.0
    cy = (bbox.bottom + bbox.top) / 2.0

    cx_mm = cx * scale
    cy_mm = cy * scale

    width_mm = (bbox.right - bbox.left) * scale
    height_mm = (bbox.top - bbox.bottom) * scale
    area_mm2 = width_mm * height_mm

    positions << [cx_mm, cy_mm]
    areas << area_mm2
  end

  if positions.empty?
    raise "No shapes found on layer #{layer}/#{datatype} in top cell #{top_cell.name}."
  end

  # detect and filter test structures by area (> TEST_SIZE_FACTOR * median)
  sorted = areas.sort
  median_area = sorted[sorted.length / 2]
  normal_positions = []
  test_positions = []
  positions.each_with_index do |pos, i|
    if areas[i] > median_area * TEST_SIZE_FACTOR
      test_positions << pos
    else
      normal_positions << pos
    end
  end

  puts "Total shapes: #{positions.length}; normal dies: #{normal_positions.length}; test structures filtered: #{test_positions.length}"
  return normal_positions, test_positions
end

# PCA for 2D points - returns centroid [cx,cy] and principal angle (radians)
# For symmetric covariance [[a,b],[b,c]] the principal axis angle = 0.5 * atan2(2b, a - c)
def pca_principal_angle(points)
  n = points.length
  cx = points.map { |p| p[0] }.inject(0.0, &:+) / n
  cy = points.map { |p| p[1] }.inject(0.0, &:+) / n

  # compute covariance elements
  sxx = 0.0
  syy = 0.0
  sxy = 0.0
  points.each do |p|
    dx = p[0] - cx
    dy = p[1] - cy
    sxx += dx * dx
    syy += dy * dy
    sxy += dx * dy
  end
  # use unbiased (not dividing by n) is fine since ratio matters
  a = sxx
  c = syy
  b = sxy

  angle = 0.5 * Math.atan2(2.0 * b, a - c)  # radians
  puts "PCA centroid: (#{cx.round(4)}, #{cy.round(4)}), principal angle (deg): #{(angle * 180.0 / Math::PI).round(4)}"
  return [cx, cy, angle]
end

def rotate_points(points, cx, cy, angle_rad)
  cos_t = Math.cos(-angle_rad)  # rotate by -theta to align principal axis to X
  sin_t = Math.sin(-angle_rad)
  rotated = points.map do |p|
    dx = p[0] - cx
    dy = p[1] - cy
    rx = cos_t * dx - sin_t * dy
    ry = sin_t * dx + cos_t * dy
    [rx + cx, ry + cy]
  end
  return rotated
end

# Estimate pitch by sampling and computing nearest neighbor distances (Euclidean)
# Returns pitch_x = pitch_y = mode of nearest-neighbor distances (binned to 0.001 mm)
def estimate_pitch_nn(points, sample_size)
  n = points.length
  sample_n = [sample_size, n].min
  sample = points.shuffle.take(sample_n)

  nn_dists = []

  sample.each_with_index do |p, i|
    min_d = Float::INFINITY
    points.each_with_index do |q, j|
      next if p.equal?(q) || (p[0] == q[0] && p[1] == q[1])
      dx = q[0] - p[0]
      dy = q[1] - p[1]
      d = Math.sqrt(dx * dx + dy * dy)
      min_d = d if d < min_d
    end
    nn_dists << min_d if min_d < Float::INFINITY
  end

  # bin to 0.001 mm
  bins = Hash.new(0)
  nn_dists.each do |d|
    bin = (d * 1000).round
    bins[bin] += 1
  end
  mode_bin, _count = bins.max_by { |k,v| v }
  pitch = mode_bin.to_f / 1000.0
  median = nn_dists.sort[nn_dists.length/2]
  puts "Nearest-neighbor: sample=#{nn_dists.length}, mode pitch=#{pitch.round(4)} mm, median=#{median.round(4)} mm"
  return [pitch, pitch]
end

# Create rectangular grid and map rotated points to grid cells
def create_grid_and_map(points, wafer_diameter_mm, pitch_x, pitch_y, tolerance_factor, force_radius_cells)
  x_list = points.map { |p| p[0] }
  y_list = points.map { |p| p[1] }
  min_x = x_list.min
  max_x = x_list.max
  min_y = y_list.min
  max_y = y_list.max

  cols = ((max_x - min_x) / pitch_x).round + 1
  rows = ((max_y - min_y) / pitch_y).round + 1
  puts "Rotated range X: #{min_x.round(3)}..#{max_x.round(3)} Y: #{min_y.round(3)}..#{max_y.round(3)}"
  puts "Grid: #{cols} cols x #{rows} rows (pitch #{pitch_x} x #{pitch_y})"

  grid = Array.new(rows) { Array.new(cols, '.') }

  cx = (min_x + max_x) / 2.0
  cy = (min_y + max_y) / 2.0
  radius = wafer_diameter_mm / 2.0

  tolerance = [pitch_x, pitch_y].max * tolerance_factor
  puts "Mapping tolerance: #{tolerance.round(4)} mm (#{(tolerance_factor*100).round(1)}% of pitch)"

  # First pass: map to best empty cell within 3x3 and tolerance
  mapped = []
  cell_map = {}  # (r,c) -> [indices] (store indices for collision handling)
  points.each_with_index do |pos, idx|
    x = pos[0]; y = pos[1]
    col_exact = (x - min_x) / pitch_x
    row_exact = (y - min_y) / pitch_y
    col_center = col_exact.round
    row_center = row_exact.round

    best = nil
    best_dist = Float::INFINITY

    (-1..1).each do |dr|
      (-1..1).each do |dc|
        tc = col_center + dc
        tr = row_center + dr
        next if tc < 0 || tc >= cols || tr < 0 || tr >= rows
        cell_x = min_x + tc * pitch_x
        cell_y = min_y + tr * pitch_y
        d = Math.sqrt((x - cell_x)**2 + (y - cell_y)**2)
        if d < best_dist && d < tolerance
          best_dist = d
          best = [tr, tc]
        end
      end
    end

    if best
      cell_map[best] ||= []
      cell_map[best] << idx
      mapped << idx
    end
  end

  mapped_count = mapped.uniq.length
  puts "PASS1: assigned to #{cell_map.length} cells, mapped dies: #{mapped_count}/#{points.length}"

  # Second pass: resolve collisions by reassigning extras to nearest empty cell (search radius grows)
  reassigned = 0
  # Build quick occupied set
  occupied = cell_map.keys.to_set

  cell_map.keys.each do |cell|
    dies = cell_map[cell]
    next if dies.length <= 1
    # keep first, reassign the rest
    dies[1..-1].each do |die_idx|
      pos = points[die_idx]
      x = pos[0]; y = pos[1]
      col = ((x - min_x) / pitch_x).round
      row = ((y - min_y) / pitch_y).round
      found = false
      (1..force_radius_cells).each do |r|
        break if found
        (-r..r).each do |dr|
          break if found
          (-r..r).each do |dc|
            tr = row + dr; tc = col + dc
            next if tc < 0 || tc >= cols || tr < 0 || tr >= rows
            next if occupied.include?([tr,tc])
            # assign here
            cell_map[[tr,tc]] = [die_idx]
            occupied.add([tr,tc])
            reassigned += 1
            found = true
            break
          end
        end
      end
      # if not found, leave as collision in original cell (will still count as mapped)
    end
    # reduce original cell to only first die
    cell_map[cell] = [dies[0]]
  end

  puts "PASS2: reassigned #{reassigned} collision dies to empty cells"

  # Build final grid characters
  mapped_cells = 0
  edge_cells = 0
  cell_map.each do |(r,c), die_indices|
    die_idx = die_indices[0]
    pos = points[die_idx]
    x = pos[0]; y = pos[1]
    dx = x - cx; dy = y - cy
    dist_from_center = Math.sqrt(dx*dx + dy*dy)
    if dist_from_center > (radius - 3.0)
      grid[r][c] = '*'
      edge_cells += 1
    else
      grid[r][c] = '?'
    end
    mapped_cells += 1
  end

  # Count dots inside wafer
  dots = 0
  (0...rows).each do |r|
    (0...cols).each do |c|
      if grid[r][c] == '.'
        x = min_x + c * pitch_x
        y = min_y + r * pitch_y
        dx = x - cx; dy = y - cy
        dots += 1 if Math.sqrt(dx*dx + dy*dy) <= radius
      end
    end
  end

  unmapped_dies = points.length - mapped_cells
  puts "RESULT: mapped_cells=#{mapped_cells}/#{points.length}, edge=#{edge_cells}, unmapped_dies=#{unmapped_dies}, dots_inside=#{dots}"
  return grid, pitch_x, pitch_y, mapped_cells, dots
end

def write_ptvs_file(grid, pitch_x, pitch_y, output_path, total_dies, mapped_count, dot_count)
  rows = grid.length
  cols = grid[0].length
  File.open(output_path, "w") do |f|
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
    # grid reversed for correct visual orientation
    grid.reverse.each do |row|
      line = row.map { |cell| "\"#{cell}\"" }.join(',')
      f.puts line
    end
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
  puts "Wrote wafer map to: #{output_path}"
end

# ================= MAIN =================
begin
  layout, top_cell = get_active_layout_and_cell
  points, tests = extract_shape_centers(layout, top_cell, SHAPE_LAYER, SHAPE_DATATYPE, EXPORT_IN_MM)

  # PCA rotation correction
  cx, cy, angle = pca_principal_angle(points)
  rotated = rotate_points(points, cx, cy, angle)

  # Estimate pitch from NN mode on rotated points
  pitch_x, pitch_y = estimate_pitch_nn(rotated, NN_SAMPLE)

  # If pitch seems zero or nil fallback to tested manual
  if pitch_x.nil? || pitch_x <= 0.0
    pitch_x = pitch_y = 1.467
    puts "Fallback pitch used: #{pitch_x}"
  end

  # Create grid and map (using rotation-corrected coordinates)
  grid, pitch_x, pitch_y, mapped_count, dot_count = create_grid_and_map(
    rotated, WAFER_DIAMETER_MM, pitch_x, pitch_y, INITIAL_TOLERANCE_FACTOR, FORCE_SEARCH_RADIUS
  )

  # Write PTVS wafer map
  write_ptvs_file(grid, pitch_x, pitch_y, OUTPUT_PATH, points.length, mapped_count, dot_count)

  RBA::MessageBox.info("Done", "Mapping complete.\nOutput: #{OUTPUT_PATH}\nMapped: #{mapped_count}/#{points.length} (#{((mapped_count.to_f/points.length)*100).round(2)}%)", RBA::MessageBox::Ok)

rescue Exception => e
  RBA::MessageBox.warning("Error", e.to_s, RBA::MessageBox::Ok)
  puts "ERROR: #{e.message}\n#{e.backtrace.join("\n")}"
end
