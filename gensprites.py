#!/usr/bin/env python3
"""Erzeugt src/sprites.inc: Pixel-Art-Sprites (10x10) als Run-Listen (row,col,len,code), Ende = 0FFh.
Codes: 0=Hintergrund 1=Koerper 2=Punkte 3=Kopf 4=Auge 5=Beine 6=Gelb 7=Weiss"""
import os
CODES = {'.':0,'B':1,'D':2,'H':3,'E':4,'L':5,'A':5,'Y':6,'W':7}
SPR = {
'bugA': """
..A....A..
...A..A...
L..HHHH..L
.LHEHHEHL.
..BBBBBB..
LBBDBBDBBL
.BBBBBBBB.
LBBDBBDBBL
..BBBBBB..
.L..BB..L.""",
'bugB': """
.A......A.
...A..A...
.L.HHHH.L.
L.HEHHEH.L
..BBBBBB..
.BBDBBDBB.
LBBBBBBBBL
.BBDBBDBB.
L.BBBBBB.L
....BB....""",
'splat': """
Y...Y...Y.
.Y..W..Y..
..YWWWWY..
.YWWYYWWY.
YYWYWWYWYY
.YWWYYWWY.
..YWWWWY..
.Y..W..Y..
Y...Y...Y.
..........""",
}
out = ['; automatisch erzeugt von tools/gensprites.py – nicht von Hand aendern']
for name, art in SPR.items():
    rows = [r for r in art.strip('\n').split('\n')]
    assert len(rows) == 10 and all(len(r) == 10 for r in rows), name
    out.append('spr_%s:' % name)
    for y, r in enumerate(rows):
        x = 0
        while x < 10:
            c = r[x]; n = 1
            while x + n < 10 and r[x + n] == c: n += 1
            out.append('    db %d,%d,%d,%d' % (y, x, n, CODES[c]))
            x += n
    out.append('    db 0FFh')
open(os.path.join(os.path.dirname(__file__), '..', 'src', 'sprites.inc'), 'w').write('\n'.join(out) + '\n')
print('sprites.inc ok')
