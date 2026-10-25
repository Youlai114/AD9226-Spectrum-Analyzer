# -*- coding: utf-8 -*-
"""把 PPM(P6) 转成 PNG, 仅依赖标准库。"""
import sys, zlib, struct


def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    # 解析 P6 头
    pos = 0
    fields = []
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            while data[pos:pos + 1] not in (b'\n', b''):
                pos += 1
            continue
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pos += 1
    assert fields[0] == b'P6', fields[0]
    w, h = int(fields[1]), int(fields[2])
    return w, h, data[pos:pos + w * h * 3]


def write_png(path, w, h, rgb):
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(tag, payload):
        return (struct.pack('>I', len(payload)) + tag + payload +
                struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


if __name__ == '__main__':
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit('.', 1)[0] + '.png'
    w, h, rgb = read_ppm(src)
    write_png(dst, w, h, rgb)
    print("wrote %s  %dx%d" % (dst, w, h))
