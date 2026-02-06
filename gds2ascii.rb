# KLayout Ruby macro - extracts die positions from GDS
# Run in Tools > Macros > Macro Development (Ruby)

mw = RBA::Application.instance.main_window
ly = mw.current_view.active_cellview.layout
top = mw.current_view.active_cellview.cell

# Configuration - ADJUST THESE FOR YOUR DESIGN
die_cell_name = "DIE"  # Replace with your actual die cell name
output_file = "wafer_layout.csv"

# Get die cell using cell_by_name (works in all KLayout versions)
die_cell = ly.cell_by_name(die_cell_name)
if !die_cell
  puts "ERROR: Die cell '#{die_cell_name}' not found!"
  puts "Available cells:"
  ly.each_cell { |cell| puts "  - #{cell.name}" }
  exit
end

# Extract die positions
die_positions = []
index = 0

top.each_inst do |inst|
  if inst.cell.name == die_cell_name
    # Get position in microns (accounting for database units)
    dbu = ly.dbu
    x = inst.trans.disp.x * dbu
    y = inst.trans.disp.y * dbu
    
    die_positions << {
      index: index,
      x: x.to_i,
      y: y.to_i,
      name: "DIE_#{index}"
    }
    index += 1
  end
end

# Write to CSV file
File.open(output_file, "w") do |f|
  f.puts "DieID,Name,X_um,Y_um"
  die_positions.each do |die|
    f.puts "#{die[:index]},#{die[:name]},#{die[:x]},#{die[:y]}"
  end
end

puts "✓ Exported #{die_positions.size} dies to #{output_file}"
