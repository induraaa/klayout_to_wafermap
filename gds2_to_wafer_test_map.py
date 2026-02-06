import re
import csv
from collections import defaultdict

# ============================================================
# 1) PARSE KLAYOUT GDS2 TEXT (YOUR WORKING LOGIC, CLEANED)
# ============================================================

def parse_gds2_wafer_map(filename):
    with open(filename, 'r', encoding="utf-8", errors="ignore") as f:
        lines = f.read().splitlines()

    structures = {}
    current_struct = None
    placements = defaultdict(list)

    i = 0
    while i < len(lines):
        line = lines[i].strip()

        if line.startswith('STRNAME'):
            current_struct = line.split()[1]
            structures[current_struct] = {}

        elif line.startswith('SREF'):
            i += 1
            sref_name = None
            x = y = None

            while i < len(lines):
                sub = lines[i].strip()

                if sub.startswith('SNAME'):
                    sref_name = sub.split()[1]

                elif sub.startswith('XY'):
                    nums = re.findall(r'-?\d+', sub)
                    if len(nums) >= 2:
                        x, y = int(nums[0]), int(nums[1])

                elif sub.startswith('ENDEL'):
                    if current_struct and sref_name and x is not None:
                        placements[current_struct].append((x, y, sref_name))
                    break
                i += 1
        i += 1

    return placements


# ============================================================
# 2) BUILD ASCII WAFER GRID (YOUR "PERFECT" MAP)
# ============================================================

def build_ascii_grid(placements, structure, w=120, h=60):
    pts = placements[structure]

    xs = [x for x, _, _ in pts]
    ys = [y for _, y, _ in pts]

    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    sx = (w - 1) / (max_x - min_x) if max_x != min_x else 1
    sy = (h - 1) / (max_y - min_y) if max_y != min_y else 1

    grid = [['.' for _ in range(w)] for _ in range(h)]

    for x, y, ref in pts:
        cx = int((x - min_x) * sx)
        cy = int((max_y - y) * sy)

        if 0 <= cx < w and 0 <= cy < h:
            if 'subdef1' in ref:
                grid[cy][cx] = '*'
            elif 'subdef2' in ref:
                grid[cy][cx] = '?'
            elif 'subdef3' in ref:
                grid[cy][cx] = '!'
            else:
                grid[cy][cx] = '*'

    return grid


# ============================================================
# 3) WRITE GRID INTO TEMPLATE TXT (2D CSV FORMAT)
# ============================================================

def is_grid_row(line):
    s = line.strip()
    return s.startswith('"."') or s.startswith('"*"') or s.startswith('"?"') or s.startswith('"!"')

def write_grid_into_template(template_path, out_path, grid):
    with open(template_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.read().splitlines(True)

    start = None
    for i, ln in enumerate(lines):
        if is_grid_row(ln):
            start = i
            break
    if start is None:
        raise RuntimeError("Template grid not found")

    end = start
    while end < len(lines) and is_grid_row(lines[end]):
        end += 1

    cols = len(next(csv.reader([lines[start]])))
    rows = end - start

    out_rows = []
    for r in range(rows):
        if r < len(grid):
            row = grid[r][:cols]
        else:
            row = ['.'] * cols

        if len(row) < cols:
            row += ['.'] * (cols - len(row))

        out_rows.append(",".join(f'"{c}"' for c in row) + "\n")

    new_lines = lines[:start] + out_rows + lines[end:]

    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.writelines(new_lines)


# ============================================================
# 4) MAIN — ONLY THINGS YOU CHANGE
# ============================================================

def main():
    gds_text = "your_layout.txt"   # KLayout GDS2 text export
    template = "/mnt/data/9PTVU6V7AA2T4Q-AT-SMA01A2-W0-V100 (3).txt"
    out_file = "wafer_output.txt"
    target_structure = "PTVSA2-xx-0xB_1205"

    placements = parse_gds2_wafer_map(gds_text)

    if target_structure not in placements:
        raise RuntimeError("Target structure not found")

    grid = build_ascii_grid(placements, target_structure)
    write_grid_into_template(template, out_file, grid)

    print("DONE.")
    print(f"Output written to: {out_file}")


if __name__ == "__main__":
    main()
