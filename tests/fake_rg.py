# A fake Jodell RG on a pty, for booting the primitive without the gripper.
# Usage: fake_rg.py <link>   (creates <link> -> the pty the primitive opens)
# Closing stops on an object at position 130 (gOBJ 2); other moves end empty (gOBJ 3).
import os, struct, sys, time, tty

OBJECT_AT = 130
STEP_PER_S = 400


def crc16(data):
    c = 0xFFFF
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
    return struct.pack("<H", c)


master, slave = os.openpty()
tty.setraw(slave)
os.symlink(os.ttyname(slave), sys.argv[1])
gsta, go, obj, pos, target, last = 0, 0, 0, 0, 0, time.monotonic()
buf = b""
while True:
    buf += os.read(master, 256)
    now = time.monotonic()
    if go and obj == 0:
        step = STEP_PER_S * (now - last)
        pos = min(target, pos + step) if target > pos else max(target, pos - step)
        if target > pos >= OBJECT_AT - 1 and target > OBJECT_AT:
            pos, obj = OBJECT_AT, 2
        elif pos == target:
            obj = 3
    last = now
    if len(buf) >= 8 and buf[1] == 0x04:
        frame, buf = buf[:8], buf[8:]
        raw = obj << 6 | gsta << 4 | go << 3 | (gsta == 3)
        body = bytes([9, 0x04, 6, 0, raw, int(pos), 0, 0, 0])
    elif len(buf) >= 9 and buf[1] == 0x10 and len(buf) >= 9 + buf[6]:
        frame, buf = buf[:9 + buf[6]], buf[9 + buf[6]:]
        words = struct.unpack(f">{frame[6] // 2}H", frame[7:-2])
        if words[0] & 1 == 0:
            gsta, go, obj = 0, 0, 0
        elif gsta == 0:
            gsta = 3  # activation sweep skipped
        if words[0] & 0x04:
            go, target = 1, int(pos)
            obj = 3
        elif words[0] & 0x08 and len(words) == 3:
            go, obj, target = 1, 0, words[1] >> 8
        body = frame[:6]
    else:
        continue
    if crc16(frame[:-2]) != frame[-2:]:
        continue
    os.write(master, body + crc16(body))
