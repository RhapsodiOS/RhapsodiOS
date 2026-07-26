"""Read Objective-C ABI facts out of a linked image's ``__OBJC`` segment.

A linked image names no methods in its symbol table beyond the ``-[Class sel]``
form, and names no ivars at all. The runtime metadata is the only source for
instance sizes, ivar offsets and type encodings, which are the parts of the ABI
that client code is compiled against.
"""

import struct


class ObjcAbiError(ValueError):
    """Raised when ``__OBJC`` metadata is absent or malformed."""


_PREFIX = {"little": "<", "big": ">"}


class ObjcReader:
    """Random access to an image by virtual address."""

    def __init__(self, payload, sections, endianness):
        self.payload = payload
        self.prefix = _PREFIX[endianness]
        self._word = struct.Struct(f"{self.prefix}I")
        self._spans = [
            (section["address"], section["size"], section["offset"])
            for section in sections
            if section.get("size")
        ]

    def offset_of(self, address):
        for start, size, offset in self._spans:
            if start <= address < start + size:
                return offset + (address - start)
        return None

    def at(self, address, count):
        """Return ``count`` 32-bit words starting at ``address``."""
        offset = self.offset_of(address)
        if offset is None or offset + 4 * count > len(self.payload):
            raise ObjcAbiError(f"address 0x{address:x} is not backed by the image")
        return struct.unpack_from(f"{self.prefix}{count}I", self.payload, offset)

    def halves(self, address, count):
        offset = self.offset_of(address)
        if offset is None or offset + 2 * count > len(self.payload):
            raise ObjcAbiError(f"address 0x{address:x} is not backed by the image")
        return struct.unpack_from(f"{self.prefix}{count}H", self.payload, offset)

    def cstring(self, address):
        if not address:
            return None
        offset = self.offset_of(address)
        if offset is None:
            raise ObjcAbiError(f"string address 0x{address:x} is not backed by the image")
        end = self.payload.find(b"\0", offset)
        if end < 0:
            raise ObjcAbiError(f"unterminated string at 0x{address:x}")
        return self.payload[offset:end].decode("latin1")

    def method_list(self, address):
        """Return ``[{selector, types}]`` for an ``objc_method_list``."""
        if not address or self.offset_of(address) is None:
            return []
        _obsolete, count = self.at(address, 2)
        methods = []
        for index in range(count):
            selector, types, _imp = self.at(address + 8 + 12 * index, 3)
            methods.append({
                "selector": self.cstring(selector),
                "types": self.cstring(types),
            })
        return methods

    def ivar_list(self, address):
        """Return ``[{name, type, offset}]`` for an ``objc_ivar_list``."""
        if not address or self.offset_of(address) is None:
            return []
        (count,) = self.at(address, 1)
        ivars = []
        for index in range(count):
            name, types, offset = self.at(address + 4 + 12 * index, 3)
            ivars.append({
                "name": self.cstring(name),
                "type": self.cstring(types),
                "offset": offset,
            })
        return ivars


def read_classes(reader, symtab_address):
    """Return the class records an ``objc_symtab`` defines."""
    _sel_ref_count, _refs = reader.at(symtab_address, 2)
    class_count, category_count = reader.halves(symtab_address + 8, 2)
    definitions = reader.at(symtab_address + 12, class_count + category_count)
    classes = []
    for pointer in definitions[:class_count]:
        (metaclass, superclass, name, _version, info,
         instance_size, ivars, method_list) = reader.at(pointer, 8)
        _mi, _ms, _mn, _mv, _minfo, _msize, _mivars, class_methods = reader.at(
            metaclass, 8
        )
        classes.append({
            "name": reader.cstring(name),
            "superclass": reader.cstring(superclass),
            "instance_size": instance_size,
            "info": info,
            "ivars": reader.ivar_list(ivars),
            "instance_methods": reader.method_list(method_list),
            "class_methods": reader.method_list(class_methods),
        })
    return classes
