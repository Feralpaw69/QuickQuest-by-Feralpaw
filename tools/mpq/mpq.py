# tiny StormLib wrapper: list / read files from MPQ archives
import ctypes, sys, os
LIB = os.environ.get('STORMLIB', '/tmp/claude-0/-home-claude/e665fc1c-eed2-545a-a2b0-bc111d12b5a9/scratchpad/StormLib/build/libstorm.so')
L = ctypes.CDLL(LIB)
H = ctypes.c_void_p
L.SFileOpenArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(H)]
L.SFileOpenFileEx.argtypes = [H, ctypes.c_char_p, ctypes.c_uint, ctypes.POINTER(H)]
L.SFileGetFileSize.argtypes = [H, ctypes.POINTER(ctypes.c_uint)]
L.SFileGetFileSize.restype = ctypes.c_uint
L.SFileReadFile.argtypes = [H, ctypes.c_void_p, ctypes.c_uint, ctypes.POINTER(ctypes.c_uint), ctypes.c_void_p]
L.SFileCloseFile.argtypes = [H]
L.SFileCloseArchive.argtypes = [H]
STREAM_FLAG_READ_ONLY = 0x100
def open_archive(path):
    h = H()
    if not L.SFileOpenArchive(path.encode(), 0, STREAM_FLAG_READ_ONLY, ctypes.byref(h)):
        raise OSError('cannot open ' + path)
    return h
def read(h, name):
    f = H()
    if not L.SFileOpenFileEx(h, name.encode(), 0, ctypes.byref(f)):
        return None
    size = L.SFileGetFileSize(f, None)
    buf = ctypes.create_string_buffer(size)
    got = ctypes.c_uint()
    L.SFileReadFile(f, buf, size, ctypes.byref(got), None)
    L.SFileCloseFile(f)
    return buf.raw[:got.value]
if __name__ == '__main__':
    h = open_archive(sys.argv[1])
    if len(sys.argv) == 2:
        lf = read(h, '(listfile)')
        print(lf.decode('latin1') if lf else 'no listfile')
    else:
        data = read(h, sys.argv[2])
        if data is None: print('missing'); sys.exit(1)
        open(sys.argv[3], 'wb').write(data); print(len(data))
