import struct
import sys


BLOCKS = [
    "autolib",
    "pkgidx",
    "file",
    "symdef",
    "hashed64def",
    "hasheddef",
    "nonpkgdef",
    "nonpkgref",
    "refflags",
    "hash64",
    "hash",
    "relocidx",
    "auxidx",
    "dataidx",
    "reloc",
    "aux",
    "data",
    "refname",
    "end",
]

PKGIDX_NONE = (1 << 31) - 1
PKGIDX_HASHED64 = PKGIDX_NONE - 1
PKGIDX_HASHED = PKGIDX_NONE - 2
PKGIDX_SELF = PKGIDX_NONE - 4
SYMBOL_SIZE = 21
RELOC_SIZE = 23
AUX_SIZE = 9

AUX_TYPES = {
    1: "funcinfo",
    7: "pcsp",
    8: "pcfile",
    9: "pcline",
    10: "pcinline",
    11: "pcdata",
}


def string_at(data, offset):
    size, string_offset = struct.unpack_from("<II", data, offset)
    return data[string_offset : string_offset + size].decode()


def read_symbols(data, start, end):
    symbols = []
    for offset in range(start, end, SYMBOL_SIZE):
        symbols.append(
            {
                "name": string_at(data, offset),
                "abi": struct.unpack_from("<H", data, offset + 8)[0],
                "type": data[offset + 10],
                "size": struct.unpack_from("<I", data, offset + 13)[0],
            }
        )
    return symbols


def main(path):
    raw = open(path, "rb").read()
    magic = bytes([0]) + b"go120ld"
    base = raw.index(magic)
    data = raw[base:]
    offsets = struct.unpack_from("<19I", data, 20)

    print("header:", raw[:base].decode().replace("\n", "\\n"))
    print("magic-offset:", base)
    print("flags:", struct.unpack_from("<I", data, 16)[0])

    for index, name in enumerate(BLOCKS):
        block_end = (
            offsets[index + 1] if index + 1 < len(offsets) else offsets[index]
        )
        print(f"{name}-bytes:", block_end - offsets[index])

    symdef = read_symbols(data, offsets[3], offsets[4])
    hashed64def = read_symbols(data, offsets[4], offsets[5])
    hasheddef = read_symbols(data, offsets[5], offsets[6])
    nonpkgdef = read_symbols(data, offsets[6], offsets[7])
    nonpkgref = read_symbols(data, offsets[7], offsets[8])

    files = []
    for offset in range(offsets[2], offsets[3], 8):
        files.append(string_at(data, offset))
    print("file-count:", len(files))
    for index, file in enumerate(files):
        print(f"file {index}: {file}")

    for label, symbols in [
        ("symdef", symdef),
        ("hashed64def", hashed64def),
        ("hasheddef", hasheddef),
        ("nonpkgdef", nonpkgdef),
        ("nonpkgref", nonpkgref),
    ]:
        print(f"{label}-count:", len(symbols))
        for index, symbol in enumerate(symbols):
            print(
                f"{label} {index}: {symbol['name']} abi={symbol['abi']} "
                f"type={symbol['type']} size={symbol['size']}"
            )

    defined = symdef + hashed64def + hasheddef + nonpkgdef
    reloc_indexes = [
        struct.unpack_from("<I", data, offsets[11] + 4 * index)[0]
        for index in range((offsets[12] - offsets[11]) // 4)
    ]
    aux_indexes = [
        struct.unpack_from("<I", data, offsets[12] + 4 * index)[0]
        for index in range((offsets[13] - offsets[12]) // 4)
    ]

    def resolve_ref(pkg_index, sym_index):
        if pkg_index == PKGIDX_NONE:
            symbols = nonpkgdef + nonpkgref
            if sym_index < len(symbols):
                return symbols[sym_index]["name"]
        if pkg_index == PKGIDX_HASHED64 and sym_index < len(hashed64def):
            return hashed64def[sym_index]["name"]
        if pkg_index == PKGIDX_HASHED and sym_index < len(hasheddef):
            return hasheddef[sym_index]["name"]
        if pkg_index == PKGIDX_SELF and sym_index < len(symdef):
            return symdef[sym_index]["name"]
        return f"{pkg_index}:{sym_index}"

    for symbol_index in range(len(defined)):
        for aux_index in range(aux_indexes[symbol_index], aux_indexes[symbol_index + 1]):
            offset = offsets[15] + aux_index * AUX_SIZE
            aux_type = data[offset]
            pkg_index, sym_index = struct.unpack_from("<II", data, offset + 1)
            aux_name = AUX_TYPES.get(aux_type, str(aux_type))
            print(
                f"aux {symbol_index}.{aux_index}: type={aux_name} "
                f"target={resolve_ref(pkg_index, sym_index)}"
            )
        for reloc_index in range(
            reloc_indexes[symbol_index], reloc_indexes[symbol_index + 1]
        ):
            offset = offsets[14] + reloc_index * RELOC_SIZE
            reloc_offset = struct.unpack_from("<i", data, offset)[0]
            size = data[offset + 4]
            reloc_type = struct.unpack_from("<H", data, offset + 5)[0]
            addend = struct.unpack_from("<q", data, offset + 7)[0]
            pkg_index, sym_index = struct.unpack_from("<II", data, offset + 15)
            print(
                f"reloc {symbol_index}.{reloc_index}: off={reloc_offset} "
                f"size={size} type={reloc_type} add={addend} "
                f"target={resolve_ref(pkg_index, sym_index)}"
            )

    print("data:", data[offsets[16] : offsets[17]].hex())


if __name__ == "__main__":
    main(sys.argv[1])
