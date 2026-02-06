import csv

# Configuration
output_file = "wafer_layout.csv"
cell_layer = 10  # Adjust to your actual layer number

# Get current layout
ly = pya.Application.instance().main_window().current_view().active_cellview().layout()
top = ly.top_cell()

# Extract die information (positions and names)
dies = []
for instance in top.each_inst():
    cell = instance.cell
    bbox = cell.bbox()
    if bbox:
        dies.append({
            'name': cell.name,
            'x': instance.cplx_trans.disp.x,
            'y': instance.cplx_trans.disp.y,
            'width': bbox.width(),
            'height': bbox.height()
        })

# Export to CSV (can be opened in Excel)
with open(output_file, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['name', 'x', 'y', 'width', 'height'])
    writer.writeheader()
    writer.writerows(dies)
