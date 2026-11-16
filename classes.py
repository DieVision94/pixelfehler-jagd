import sys,struct,glob
sys.path.insert(0,'/workspace/geos-mouse/tools')
from geos1dump import Geode
for f in sorted(glob.glob(sys.argv[1])):
    try: g=Geode(open(f,'rb').read(),f)
    except Exception as e: continue
    for ri,r in enumerate(g.res):
        if r['flags']&0x0400: continue
        for rl in r['relocs']:
            info,extra,off=rl
            if info==0x11 or info==0x00 and False:
                d=r['data']
                if off+0x12>len(d): continue
                cnt=struct.unpack_from('<H',d,off+6)[0]
                if not 0<cnt<200: continue
                msgs=struct.unpack_from('<%dH'%cnt,d,off+0x12)
                print(f.split('/')[-1],'res%d:%04X'%(ri,off),'lib%d'%extra,' '.join('%04X'%m for m in msgs))
