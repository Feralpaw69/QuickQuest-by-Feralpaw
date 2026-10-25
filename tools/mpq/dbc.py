import struct
def load(path):
    d=open(path,'rb').read()
    magic,n,fields,rsize,ssize=struct.unpack('<4s4I',d[:20])
    assert magic==b'WDBC'
    rows=[d[20+i*rsize:20+(i+1)*rsize] for i in range(n)]
    strings=d[20+n*rsize:]
    def s(off):
        e=strings.index(b'\0',off); return strings[off:e].decode('utf8','replace')
    return rows,fields,rsize,s
