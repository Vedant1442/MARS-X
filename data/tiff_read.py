"""Minimal stdlib TIFF/COG reader (little-endian, classic or BigTIFF, tiled, deflate, predictor 1/2/3)."""
import struct, zlib
TS={1:1,2:1,3:2,4:4,5:8,6:1,7:1,8:2,9:4,10:8,11:4,12:8,16:8,17:8,18:8}
FM={1:'B',2:'c',3:'H',4:'I',6:'b',8:'h',9:'i',11:'f',12:'d',16:'Q',17:'q'}
TAGS={256:'w',257:'h',258:'bps',259:'comp',277:'spp',317:'pred',322:'tw',323:'th',324:'toff',325:'tcnt',339:'fmt',33550:'scale',33922:'tie',42113:'nodata',254:'subfile'}
def read_ifds(d):
    assert d[:2]==b'II'; big=struct.unpack('<H',d[2:4])[0]==43
    ifd=struct.unpack('<Q',d[8:16])[0] if big else struct.unpack('<I',d[4:8])[0]
    L='Q' if big else 'I'; out=[]
    while ifd:
        n=struct.unpack('<'+('Q' if big else 'H'),d[ifd:ifd+(8 if big else 2)])[0]; p=ifd+(8 if big else 2); esz=20 if big else 12; e={}
        for i in range(n):
            ent=d[p+i*esz:p+(i+1)*esz]; tag,typ=struct.unpack('<HH',ent[:4])
            cnt=struct.unpack('<'+L,ent[4:4+(8 if big else 4)])[0]; vo=ent[12:] if big else ent[8:]
            sz=TS.get(typ,1)*cnt
            raw=vo[:sz] if sz<=(8 if big else 4) else d[struct.unpack('<'+L,vo[:8 if big else 4])[0]:][:sz]
            if tag in TAGS and typ in FM:
                e[TAGS[tag]]=struct.unpack('<'+str(cnt)+FM[typ],raw)
            elif tag in TAGS and typ==2: e[TAGS[tag]]=raw
        out.append(e); nxt=p+n*esz
        ifd=struct.unpack('<'+L,d[nxt:nxt+(8 if big else 4)])[0]
    return out
def read_tile(d,e,i):
    raw=zlib.decompress(d[e['toff'][i]:e['toff'][i]+e['tcnt'][i]])
    tw,th=e['tw'][0],e['th'][0]; pred=e.get('pred',(1,))[0]; bps=e['bps'][0]//8
    if pred==2:  # horizontal differencing on 32-bit words
        w=list(struct.unpack('<%dI'%(tw*th),raw))
        for r in range(th):
            b=r*tw
            for k in range(1,tw): w[b+k]=(w[b+k]+w[b+k-1])&0xFFFFFFFF
        raw=struct.pack('<%dI'%(tw*th),*w)
    return struct.unpack('<%df'%(tw*th),raw)

def read_level(d,e):
    """Decode a whole IFD level into rows of floats (nodata -> None)."""
    W,H,tw,th=e['w'][0],e['h'][0],e['tw'][0],e['th'][0]; nx=(W+tw-1)//tw
    rows=[[None]*W for _ in range(H)]
    for i in range(len(e['toff'])):
        t=read_tile(d,e,i); x0=(i%nx)*tw; y0=(i//nx)*th
        for r in range(min(th,H-y0)):
            seg=t[r*tw:r*tw+min(tw,W-x0)]
            rows[y0+r][x0:x0+len(seg)]=[None if (v<-1e30 or v!=v) else v for v in seg]
    return rows
