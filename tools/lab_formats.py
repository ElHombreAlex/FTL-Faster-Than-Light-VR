"""Local FTL lab converters. Never distribute their game-derived output."""
import struct
import zlib
from pathlib import Path

from extract_ftl import Pkg


def path_hash(name: str) -> int:
    """SIL PKG rotate/XOR path hash, documented by Slipstream PkgPack."""
    value = 0
    for byte in name.lower().encode('ascii'):
        value = (((value << 27) | (value >> 5)) ^ byte) & 0xFFFFFFFF
    return value


def write_pkg(source: Path, destination: Path, replacements: dict[str, bytes]):
    pkg = Pkg(source)
    names = sorted(set(pkg.entries) | set(replacements), key=lambda n: (path_hash(n), n.lower()))
    name_blob = b''.join(n.encode('ascii') + b'\0' for n in names)
    offset = 16 + 20 * len(names) + len(name_blob)
    name_offset = 0
    index = []
    for name in names:
        size = len(replacements[name]) if name in replacements else pkg.entries[name][2]
        index.append(struct.pack('>IIIII', path_hash(name), name_offset, offset, size, size))
        offset += size
        name_offset += len(name.encode('ascii')) + 1
    if len(name_blob) >= 1 << 24 or offset >= 1 << 32:
        raise ValueError('PKG exceeds format bounds')
    if source.resolve() == destination.resolve():
        raise ValueError('Refusing to overwrite source archive')
    with destination.open('wb') as output:
        output.write(b'PKG\n' + struct.pack('>HHII', 16, 20, len(names), len(name_blob)))
        output.write(b''.join(index))
        output.write(name_blob)
        for name in names:
            output.write(replacements[name] if name in replacements else pkg.read(name))
    check = Pkg(destination)
    for name, payload in replacements.items():
        if check.read(name) != payload:
            raise ValueError(f'PKG round trip failed: {name}')


def apply_bps(source: bytes, patch: bytes) -> bytes:
    """Apply a BPS patch with source, patch, and target CRC checks."""
    if patch[:4] != b'BPS1' or len(patch) < 16:
        raise ValueError('Not a BPS patch')
    source_crc, target_crc, patch_crc = struct.unpack('<III', patch[-12:])
    if zlib.crc32(source) != source_crc or zlib.crc32(patch[:-4]) != patch_crc:
        raise ValueError('Source or patch CRC mismatch')
    cursor = 4

    def number():
        nonlocal cursor
        value, shift = 0, 1
        while True:
            if cursor >= len(patch) - 12:
                raise ValueError('Truncated BPS number')
            byte = patch[cursor]
            cursor += 1
            value += (byte & 127) * shift
            if byte & 128:
                return value
            shift <<= 7
            value += shift

    source_size, target_size, metadata_size = number(), number(), number()
    if source_size != len(source) or target_size > 128 * 1024 * 1024:
        raise ValueError('Unsupported BPS sizes')
    cursor += metadata_size
    target = bytearray()
    source_relative = target_relative = 0
    while len(target) < target_size:
        action = number()
        mode, count = action & 3, (action >> 2) + 1
        if len(target) + count > target_size:
            raise ValueError('BPS target overrun')
        if mode == 0:
            start = len(target)
            if start + count > len(source):
                raise ValueError('BPS source overrun')
            target.extend(source[start:start + count])
        elif mode == 1:
            if cursor + count > len(patch) - 12:
                raise ValueError('BPS literal overrun')
            target.extend(patch[cursor:cursor + count])
            cursor += count
        else:
            distance = number()
            delta = (distance >> 1) * (-1 if distance & 1 else 1)
            if mode == 2:
                source_relative += delta
                if source_relative < 0 or source_relative + count > len(source):
                    raise ValueError('BPS source copy out of bounds')
                target.extend(source[source_relative:source_relative + count])
                source_relative += count
            else:
                target_relative += delta
                for _ in range(count):
                    if not 0 <= target_relative < len(target):
                        raise ValueError('BPS target copy out of bounds')
                    target.append(target[target_relative])
                    target_relative += 1
    if cursor != len(patch) - 12 or zlib.crc32(target) != target_crc:
        raise ValueError('BPS target CRC or trailing data mismatch')
    return bytes(target)
