#!/usr/bin/env python3
# Generates gfx/doom/{doom_consts.asm,doom_data.asm,doom_tiles.2bpp} for the DOOM minigame. Run from the repo root.
import math, sys
from collections import deque
from PIL import Image

PHQ = int(sys.argv[1]) if len(sys.argv) > 1 else 1   # wall height quantum (px); raise if the tile pool overflows 256
SCR = '/private/tmp/claude-501/-Users-octaviosanti-projects-personales-prueba-pokered-mac/b9f03cce-cdbb-41c6-ae8d-29b4b2ce1bfb/scratchpad'
MAXN, NCOLS, VROWS, NANG = 80, 20, 15, 64
GUN = ["      ####      ", "      #..#      ", "      #..#      ", "      #oo#      ", "      #oo#      ", "     ##oo##     ",
       "     #o..o#     ", "    #oo..oo#    ", "    #o....o#    ", "   ##oooooo##   ", "   #o.####.o#   ", "  #oo.#oo#.oo#  ",
       "  #o..#oo#..o#  ", " #oo...#oo#...oo# ", " #o....#oo#....o# ", "#oo....#oo#....oo#"]
MAP = ["################", "#..............#", "#..##......##..#", "#..#........#..#", "#......##......#", "#......##......#",
       "#..#........#..#", "#..##......##..#", "#..............#", "#..###....###..#", "#..............#", "#....#....#....#",
       "#....#....#....#", "#..............#", "#..............#", "################"]
ENEMIES = "pikachu gengar charmander geodude gastly voltorb".split()
DIG = ["111 101 101 101 111", "010 110 010 010 111", "111 001 111 100 111", "111 001 111 001 111", "101 101 111 001 001",
       "111 100 111 001 111", "111 100 111 101 111", "111 001 001 001 001", "111 101 111 101 111", "111 101 111 001 111"]

pool, index = [], {}   # tiles: tuple of 64 shades row-major
def tile(px):
    px = tuple(px)
    if px not in index: index[px] = len(pool); pool.append(px)
    return index[px]
def blocks(img, w, h):   # img: 2D list [y][x] -> row-major list of tile ids
    return [tile(img[ty * 8 + y][tx * 8 + x] for y in range(8) for x in range(8)) for ty in range(h // 8) for tx in range(w // 8)]
def grid(w, h, f): return [[f(x, y) for x in range(w)] for y in range(h)]

consts = {}

# fixed groups are appended without dedupe so they stay contiguous
def group(name, imgs):
    consts[name] = len(pool)
    for px in imgs: pool.append(tuple(px))
def flat(img, w, h): return [[tuple(img[ty * 8 + y][tx * 8 + x] for y in range(8) for x in range(8)) for tx in range(w // 8)] for ty in range(h // 8)]
def tiles_of(img, w, h): return [t for row in flat(img, w, h) for t in row]

group('DOOM_T_BLACK', [[3] * 64])
# face: Red's head
red = Image.open('gfx/player/red.png').convert('L').crop((10, 1, 36, 27)).resize((24, 24), Image.BOX)
f = [[3 - round(red.getpixel((x, y)) / 85) for x in range(24)] for y in range(24)]
group('DOOM_T_FACE', tiles_of(f, 24, 24))
group('DOOM_T_FACE_HURT', tiles_of([[3 - c for c in r] for r in f], 24, 24))
# digits: 5x7 glyph scaled from 3x5 font (cols x1.5 is ugly) -> draw 3x5 at 1x with 1px margin doubled vertically? use 3x5 cells of 2x1 px => 6x5; keep readable: 3 wide x2, 5 tall x1+ -> 6x7
def glyph(rows):   # 3x5 font cells -> 2px wide, rows mapped onto 7 px
    img = grid(8, 8, lambda x, y: 3)
    # 6x7: each font cell is 2px wide; rows: 0,1 | 2 | 3 | 4 | 5,6 -> map 5 font rows to 7 px rows
    ymap = [(0,), (1, 2), (3,), (4, 5), (6,)]
    for r, s in enumerate(rows.split()):
        for c, ch in enumerate(s):
            if ch == '1':
                for dy in ymap[r]:
                    for dx in (0, 1): img[dy][1 + c * 2 + dx] = 0
    return img
group('DOOM_T_DIGIT', [t for d in DIG for t in tiles_of(glyph(d), 8, 8)])
def bar(i):
    img = grid(8, 8, lambda x, y: 3)
    for x in range(8):
        for y in (1, 6): img[y][x] = 2
        for y in range(2, 6): img[y][x] = 1 if x < i else 3
    return img
group('DOOM_T_BAR', [t for i in range(9) for t in tiles_of(bar(i), 8, 8)])
bul = ["........", "...00...", "..0000..", "..0220..", "..0220..", "..0220..", "..0000..", "........"]
group('DOOM_T_BULLET', tiles_of([[3 if ch == '.' else int(ch) for ch in r] for r in bul], 8, 8))
# gun 16x16 -> 2x
G = [(r[(len(r) - 16) // 2:(len(r) - 16) // 2 + 16] if len(r) > 16 else r.ljust(16)) for r in GUN]
gi = grid(32, 32, lambda x, y: {' ': 0, '.': 1, 'o': 2, '#': 3}[G[y // 2][x // 2]])
group('DOOM_T_GUN', tiles_of(gi, 32, 32))
# muzzle flash 16x16: star burst, 1 = glow, 3 = core... color 0 transparent
def fl(x, y):
    d = abs(x - 7.5) + abs(y - 7.5)
    if d < 3: return 1
    if d < 6 or abs(x - 7.5) < 1.5 and abs(y - 7.5) < 7 or abs(y - 7.5) < 1.5 and abs(x - 7.5) < 7: return 2
    return 0
fi = grid(16, 16, lambda x, y: 0 if (x, y) == (0, 0) else fl(x, y))
for y in range(16):
    for x in range(16):
        if fl(x, y) == 2 and abs(x - 7.5) + abs(y - 7.5) > 8: fi[y][x] = 0
        if abs(x - 7.5) + abs(y - 7.5) < 4: fi[y][x] = 1
group('DOOM_T_FLASH', tiles_of(fi, 16, 16))
# enemies
def sprite(name, size):
    im = Image.open(f'gfx/pokemon/front/{name}.png').convert('L').resize((size, size), Image.BOX)
    p = [[3 - round(im.getpixel((x, y)) / 85) for x in range(size)] for y in range(size)]
    bg = [[False] * size for _ in range(size)]   # flood-fill shade-0 from the border = transparent
    q = deque((x, y) for x in range(size) for y in range(size) if x in (0, size - 1) or y in (0, size - 1))
    while q:
        x, y = q.popleft()
        if not (0 <= x < size and 0 <= y < size) or bg[y][x] or p[y][x] != 0: continue
        bg[y][x] = True
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return [[0 if bg[y][x] else max(p[y][x], 1) for x in range(size)] for y in range(size)]
consts['DOOM_T_ENEMY'] = len(pool)
for n in ENEMIES:
    for sz in (16, 24):
        for t in tiles_of(sprite(n, sz), sz, sz): pool.append(tuple(t))

# walls: pixel-exact tiles, deduped (appended after the fixed groups)
CEIL = lambda x, y: 2
FLOOR = lambda x, y: (x + y) & 1
WALLS = [  # [bucket][parity] -> f(x,y)
    [lambda x, y: 3, lambda x, y: 3 - (x & 1)],
    [lambda x, y: 3 - 2 * (x & 1), lambda x, y: 2 + (x & 1)],
    [lambda x, y: 2 - (x & 1), lambda x, y: 1]]
def pat_tile(r, y0, y1, wf):
    return tile(tuple((CEIL if 8 * r + y < y0 else wf if 8 * r + y < y1 else FLOOR)(x, 8 * r + y) for y in range(8) for x in range(8)))
consts['DOOM_T_WALLS'] = len(pool)
pat = []
for par in (0, 1):
    for n in range(MAXN + 1):
        if n == 0: y0 = y1 = 60; wf = WALLS[0][0]
        else:
            ph = min(120, round(960 / n)); ph = max(PHQ, round(ph / PHQ) * PHQ) if ph < 120 else 120
            y0 = (120 - ph) // 2; y1 = y0 + ph
            wf = WALLS[0 if n <= 24 else 1 if n <= 48 else 2][par]
        pat += [pat_tile(r, y0, y1, wf) for r in range(VROWS)]
assert len(pool) <= 256, f'tile pool {len(pool)} > 256: rerun with larger PHQ'

# tables
rays = bytearray(); 
for a in range(NANG):
    c, s = math.cos(2 * math.pi * a / NANG), math.sin(2 * math.pi * a / NANG)
    for col in range(NCOLS):
        cx = 2 * (col + .5) / NCOLS - 1
        for v in (c + (-s) * .625 * cx, s + c * .625 * cx):
            r = round(v * 32); assert -128 <= r <= 127; rays.append(r & 255)
cos = [round(64 * math.cos(2 * math.pi * a / NANG)) for a in range(NANG)]
sin = [round(64 * math.sin(2 * math.pi * a / NANG)) for a in range(NANG)]
def db(name, vals, per=16):
    o = f'{name}::\n'
    for i in range(0, len(vals), per): o += '\tdb ' + ', '.join(f'${v & 255:02x}' for v in vals[i:i + per]) + '\n'
    return o

with open('gfx/doom/doom_tiles.2bpp', 'wb') as f:
    for t in pool:
        for y in range(8):
            row = t[y * 8:y * 8 + 8]
            f.write(bytes([sum((c & 1) << (7 - x) for x, c in enumerate(row)), sum((c >> 1) << (7 - x) for x, c in enumerate(row))]))
with open('gfx/doom/doom_consts.asm', 'w') as f:
    f.write('; generated by tools/gen_doom.py\n')
    for k, v in dict(DOOM_MAXN=MAXN, DOOM_NCOLS=NCOLS, DOOM_VROWS=VROWS, DOOM_NANGLES=NANG, DOOM_TILE_COUNT=len(pool), **consts).items():
        f.write(f'DEF {k} EQU {v}\n')
    f.write('DEF DOOM_PLAYER_X EQU 8\nDEF DOOM_PLAYER_Y EQU 8 ; start tile (map units)\n')
with open('gfx/doom/doom_data.asm', 'w') as f:
    f.write('; generated by tools/gen_doom.py\nDoomTiles::\n\tINCBIN "gfx/doom/doom_tiles.2bpp"\nDoomTilesEnd::\n\n')
    f.write('; ((parity*(DOOM_MAXN+1) + n)*DOOM_VROWS + row) -> tile id\n' + db('DoomPat', pat, 15) + '\n')
    f.write('; (angle*DOOM_NCOLS + col)*2 -> signed dx, dy (1/256 tile per march step)\n' + db('DoomRays', list(rays), 20) + '\n')
    f.write(db('DoomCos', cos) + '\n' + db('DoomSin', sin) + '\n')
    f.write('\nSECTION "Doom Map", ROMX, ALIGN[8]\n; 16x16, 1 = wall\n' + db('DoomMap', [1 if ch == '#' else 0 for r in MAP for ch in r], 16))

# previews
sheet = Image.new('L', (16 * 8 * 3, ((len(pool) + 15) // 16) * 8 * 3))
for i, t in enumerate(pool):
    im = Image.new('L', (8, 8)); im.putdata([255 - v * 85 for v in t])
    sheet.paste(im.resize((24, 24), Image.NEAREST), ((i % 16) * 24, (i // 16) * 24))
sheet.save(f'{SCR}/doom_pool.png')
view = Image.new('L', (160, 120))
for c in range(20):
    n = [0, 6, 14, 30, 60][c // 4]; pr = c & 1
    for r in range(15):
        t = pool[pat[(pr * (MAXN + 1) + n) * VROWS + r]]
        im = Image.new('L', (8, 8)); im.putdata([255 - v * 85 for v in t]); view.paste(im, (c * 8, r * 8))
view.resize((480, 360), Image.NEAREST).save(f'{SCR}/doom_walls.png')
print('tiles', len(pool), 'wall tiles', len(pool) - consts['DOOM_T_WALLS'], 'PHQ', PHQ)
