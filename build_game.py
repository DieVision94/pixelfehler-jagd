#!/usr/bin/env python3
"""build_game.py – baut build/PIXJAGD.GEO (GeoWorks 1.x App) aus src/pixjagd.asm.

Vorgehen: Vorlage = BOUNCE.GEO (1.x, 3572 Bytes, GeoWorks-Demo). Uebernommen werden Geode-Header,
Import-Tabelle (ui) und die UI-Objektbloecke (GenApplication/GenPrimary/Liste/GenView + Icons).
Ersetzt werden:
  res1 (dgroup): neue Prozessklasse (Methodentabelle -> eigene Handler) + Spielvariablen
  res2 (Code):   komplett eigener Code (NASM), Kernel-Aufrufe als KERNEL/FAR_PTR-Relocations
  UI-Texte (Titel, Liste "Spiel: Laeuft/Pause"), View-Groesse 480x320, View-Hintergrund schwarz,
  Header: Langname, Token, permanenter Name.
Aufruf: python3 tools/build_game.py   (Ergebnis + SHA256 auf stdout)
"""
import os, sys, struct, subprocess, hashlib, re
G = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, '/workspace/geos-mouse/tools')
import geos1link
TEMPLATE = '/workspace/geos-mouse/zip2/GEOWORKS/WORLD/BOUNCE.GEO'
OUT = os.path.join(G, 'build', os.environ.get('OUTNAME', 'PIXJAGD.GEO'))
W = lambda d, o: struct.unpack_from('<H', d, o)[0]
def al(v, a): return (v + a - 1) // a * a

METHODS = [(0x0049, 'M_Exposed'), (0x0057, 'M_WinClosed'), (0x00C3, 'M_Click'),
           (0x0C00, 'M_Pause'), (0x0C01, 'M_Tick'), (0x0A03, 'M_CloseApp')]
CLASSOFF = 0x40
STACK = 3000
LONGNAME = 'Pixelfehler-Jagd'
TOKEN = b'PXJG'

# ---------- LMem-Hilfen (1.x-Layout wie in BOUNCE verifiziert) ----------
def lmem_chunks(d):
    hoff, n = W(d, 2), W(d, 0x0A)
    return hoff, n, [W(d, hoff + 2 * i) for i in range(n)]

def lmem_rebuild(d, repl):
    """repl: {handleIndex: neue Chunkdaten}. Chunks werden neu gepackt (Daten @4n+2, Groessenwort = len+2)."""
    d = bytearray(d)
    hoff, n, ptrs = lmem_chunks(d)
    live = sorted((p, i) for i, p in enumerate(ptrs) if p not in (0, 0xFFFF))
    first = live[0][0]
    head = d[:first - 2]
    datas = {}
    for p, i in live:
        datas[i] = repl.get(i, bytes(d[p:p + W(d, p - 2) - 2]))
    out = bytearray(head)
    pos = first
    for p, i in live:
        while len(out) < pos - 2: out.append(0)
        b = datas[i]
        out += struct.pack('<H', len(b) + 2) + b
        struct.pack_into('<H', out, hoff + 2 * i, pos)
        pos = al(pos + len(b), 4) + 2
    end = al(len(out), 4)
    out += b'\0' * (end - len(out))
    struct.pack_into('<H', out, 0x08, end)          # LMBH_blockSize
    out += b'\0' * (al(end, 16) - end)
    assert W(d, 0x14) == len(d)                      # Objektblock: Ressourcengroesse (1.x @0x14)
    struct.pack_into('<H', out, 0x14, len(out))
    return out

def find_text_chunk(d, text):
    hoff, n, ptrs = lmem_chunks(d)
    for i, p in enumerate(ptrs):
        if p in (0, 0xFFFF): continue
        c = bytes(d[p:p + W(d, p - 2) - 2])
        if c.endswith(text.encode('mac_roman') + b'\0') and len(c) == 6 + len(text) + 1:
            return i, c
    raise SystemExit('Text-Chunk nicht gefunden: %r' % text)

def set_text(d, repl, old, new):
    i, c = find_text_chunk(d, old)
    repl[i] = c[:6] + new.encode('mac_roman') + b'\0'


# ---------- Icons (GString mit GR_DRAW_BITMAP 1Ah, PackBits) ----------
BUG = ["..A....A..", "...A..A...", "L..HHHH..L", ".LHEHHEHL.", "..BBBBBB..",
       "LBBDBBDBBL", ".BBBBBBBB.", "LBBDBBDBBL", "..BBBBBB..", ".L..BB..L."]
def packbits(b):
    out = bytearray(); i = 0
    while i < len(b):
        j = i
        while j + 1 < len(b) and b[j + 1] == b[i] and j - i < 127: j += 1
        if j > i:
            out += bytes([(256 - (j - i)) & 0xFF, b[i]]); i = j + 1
        else:
            k = i
            while k + 1 < len(b) and k - i < 127 and not (k + 2 < len(b) and b[k + 1] == b[k + 2]): k += 1
            out += bytes([k - i]) + b[i:k + 1]; i = k + 1
    return bytes(out)

def icon_pixels(w, h, sc, color):
    """Pixel-Bug zentriert + Fadenkreuz-Ecken; liefert dict (x,y)->Farbe."""
    pal = {'A': 8, 'L': 8, 'H': 8, 'E': 15, 'B': 12, 'D': 0} if color else \
          {'A': 0, 'L': 0, 'H': 0, 'E': 15, 'B': 0, 'D': 15}
    px = {}
    ox, oy = (w - 10 * sc) // 2, (h - 10 * sc) // 2
    for y, row in enumerate(BUG):
        for x, c in enumerate(row):
            if c == '.': continue
            for dy in range(sc):
                for dx in range(sc): px[(ox + x * sc + dx, oy + y * sc + dy)] = pal[c]
    # Fadenkreuz-Ecken
    cc = 14 if color else 0
    for (cx, cy, sx, sy) in ((ox - 4, oy, 1, 1), (ox + 10 * sc + 3, oy, -1, 1),
                             (ox - 4, oy + 10 * sc - 1, 1, -1), (ox + 10 * sc + 3, oy + 10 * sc - 1, -1, -1)):
        for t in range(5):
            if 0 <= cx + sx * t < w: px[(cx + sx * t, cy)] = cc
            if 0 <= cy + sy * t < h: px[(cx, cy + sy * t)] = cc
    return px

def icon_moniker(oldchunk, color):
    vmtype, w, h = oldchunk[0], W(oldchunk, 1), W(oldchunk, 3)
    assert oldchunk[5] == 0x1A
    btype = oldchunk[8 + 5]
    sc = 3 if h >= 30 else (1 if h < 20 else 1)
    px = icon_pixels(w, h, max(1, min(sc, (h - 2) // 10, (w - 10) // 10)), color)
    rows = bytearray()
    for y in range(h):
        if btype == 0x11:                       # 4 Bit + Maske
            mask = bytearray((w + 7) // 8); data = bytearray((w + 1) // 2)
            for x in range(w):
                if (x, y) in px:
                    mask[x // 8] |= 0x80 >> (x % 8)
                    data[x // 2] |= px[(x, y)] << (4 if x % 2 == 0 else 0)
            rows += packbits(bytes(mask + data))
        elif btype == 0x00:                     # mono: 1 = schwarz
            data = bytearray((w + 7) // 8)
            for x in range(w):
                if px.get((x, y), 15) == 0: data[x // 8] |= 0x80 >> (x % 8)
            rows += packbits(bytes(data))
        else:
            raise SystemExit('Bitmaptyp %02x?' % btype)
    bm = struct.pack('<HHBB', w, h, 1, btype) + rows
    return bytes([vmtype]) + struct.pack('<HH', w, h) + b'\x1a' + struct.pack('<H', len(bm)) + bm + b'\x00'

def replace_icon(g, ri):
    d = bytearray(g.res[ri]['data'])
    hoff, n, ptrs = lmem_chunks(d)
    for i, p in enumerate(ptrs):
        if p in (0, 0xFFFF): continue
        c = bytes(d[p:p + W(d, p - 2) - 2])
        if len(c) > 9 and c[5] == 0x1A:
            btype = c[13]
            g.res[ri]['data'] = lmem_rebuild(d, {i: icon_moniker(c, btype == 0x11)})
            return '%dx%d %s' % (W(c, 1), W(c, 3), 'farbig' if btype == 0x11 else 'mono')
    return None

# ---------- Build ----------
def main():
    subprocess.check_call([sys.executable, os.path.join(G, 'tools', 'gensprites.py')])
    subprocess.check_call([sys.executable, os.path.join(G, 'tools', 'genstrings.py')])
    nmeth = len(METHODS)
    cls_end = CLASSOFF + 0x12 + 6 * nmeth
    DBASE = al(cls_end, 16)
    bdir = os.path.join(G, 'build'); os.makedirs(bdir, exist_ok=True)
    wrap = os.path.join(bdir, 'wrap.asm')
    open(wrap, 'w').write('[map all pixjagd.map]\nDBASE equ 0x%X\nCLASSOFF equ 0x%X\n%s%%include "pixjagd.asm"\n' % (DBASE, CLASSOFF, '%define TESTFREEZE\n' if os.environ.get('TEST') else ''))
    subprocess.check_call([os.path.join(G, 'tools', 'nasm'), '-f', 'bin', '-I', os.path.join(G, 'src') + '/', '-o', 'code.bin', '-l', 'code.lst', 'wrap.asm'], cwd=bdir)
    code = bytearray(open(os.path.join(bdir, 'code.bin'), 'rb').read())
    sym = {}
    for line in open(os.path.join(bdir, 'pixjagd.map')):
        m = re.match(r'\s*([0-9A-F]+)\s+([0-9A-F]+)\s+(\S+)\s*$', line) or re.match(r'\s*([0-9A-F]+)\s+(\S+)\s*$', line)
        if m: sym[m.groups()[-1]] = int(m.group(1), 16)
    krel = sorted(v for k, v in sym.items() if re.match(r'\.\.@KR_\d+$', k))
    vend = sym['v_end']
    g = geos1link.load(TEMPLATE)
    hdr = bytearray(g.d)
    # ---- Header ----
    hdr[0x20:0x44] = LONGNAME.encode('mac_roman').ljust(36, b'\0')
    hdr[0xA8:0xC8] = b'(c) 2026 Grok Bot fuer V.M.'.ljust(32, b'\0')
    hdr[0x14:0x18] = TOKEN; hdr[0x100:0x104] = TOKEN
    hdr[0xF4:0x100] = b'pixjagd .app'
    # ---- res1: dgroup ----
    r1size = al(vend, 16)
    d1 = bytearray(r1size)
    struct.pack_into('<H', d1, 0x14, r1size)              # Stack-Anfang (Ende der Daten)
    struct.pack_into('<HHHH', d1, CLASSOFF + 4, 0, nmeth, 4, 0)
    d1[CLASSOFF + 0x10:CLASSOFF + 0x12] = b'\x08\x01'
    rel1 = [(0x11, 0, CLASSOFF), (0x12, 0, CLASSOFF + 2)]
    for k, (msg, lbl) in enumerate(METHODS):
        struct.pack_into('<H', d1, CLASSOFF + 0x12 + 2 * k, msg)
        fo = CLASSOFF + 0x12 + 2 * nmeth + 4 * k
        struct.pack_into('<HH', d1, fo, sym[lbl], 2)
        rel1.append((0x22, 0, fo + 2))
    g.res[1]['data'] = d1; g.res[1]['relocs'] = rel1
    struct.pack_into('<H', hdr, 0xD6, STACK)              # udata = Stack (keine BSS)
    # ---- res2: Code ----
    for o in krel: assert code[o - 1] == 0x9A, hex(o)
    code += b'\0' * (al(len(code), 16) - len(code))
    g.res[2]['data'] = code; g.res[2]['relocs'] = [(0x00, 0, o) for o in krel]
    # ---- UI: res3 (Interface) ----
    d3 = bytearray(g.res[3]['data'])
    vs = d3.find(bytes.fromhex('c8004600'))
    assert vs > 0
    struct.pack_into('<HH', d3, vs, 480, 320)             # HINT_INITIAL_SIZE
    assert d3[vs - 8] == 0x0F; d3[vs - 8] = 0x00          # View-Hintergrund: weiss -> schwarz
    repl = {}
    set_text(d3, repl, 'Bounce', LONGNAME)
    set_text(d3, repl, 'Status:', 'Spiel:')
    set_text(d3, repl, 'An', 'L\u00e4uft')
    set_text(d3, repl, 'Aus', 'Pause')
    g.res[3]['data'] = lmem_rebuild(d3, repl)
    # ---- res4 (GenApplication) ----
    d4 = bytearray(g.res[4]['data'])
    t = d4.find(b'BONC'); assert t > 0; d4[t:t + 4] = TOKEN
    repl = {}
    set_text(d4, repl, 'Bounce', LONGNAME)
    g.res[4]['data'] = lmem_rebuild(d4, repl)
    for ri in range(5, 11):
        r = replace_icon(g, ri)
        print('  Icon res%d: %s' % (ri, r))
    g.d = bytes(hdr)
    out = geos1link.serialize(g)
    open(OUT, 'wb').write(out)
    print('code %d Bytes, dgroup %d (Variablen ab 0x%X), %d Kernel-Relocs' % (len(code), r1size, DBASE, len(krel)))
    for msg, lbl in METHODS: print('  MSG %04X -> %s @%04X' % (msg, lbl, sym[lbl]))
    print('%s %d Bytes sha256 %s' % (OUT, len(out), hashlib.sha256(out).hexdigest()))

if __name__ == '__main__':
    main()
