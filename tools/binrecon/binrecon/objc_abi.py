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

    def __init__(self, payload, sections, endianness, method_names=None):
        self.payload = payload
        # imp address -> "-[Class selector]", consulted when a selector pointer
        # was rewritten by prebinding to an address outside this image.
        self.method_names = method_names or {}
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
            selector, types, imp = self.at(address + 8 + 12 * index, 3)
            methods.append({
                "selector": self.selector(selector, imp),
                "types": self.cstring(types),
            })
        return methods

    def selector(self, address, imp):
        """Name a method's selector, tolerating prebound selector pointers.

        The reference is a prebound dylib: the static linker rewrote 369 of its
        3,253 method-name pointers to uniqued selectors in the shared runtime's
        table, at addresses outside this image. Those are recovered from the
        symbol table, where the method is named ``-[Class selector]`` or
        ``+[Class(Category) selector]``.
        """
        if self.offset_of(address) is not None:
            return self.cstring(address)
        symbol = self.method_names.get(imp)
        if symbol is None:
            raise ObjcAbiError(
                f"selector pointer 0x{address:x} is outside the image and no "
                f"symbol names the method implemented at 0x{imp:x}"
            )
        return symbol[symbol.index(" ") + 1:-1]

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


def method_symbol_index(document):
    """Map each method's implementation address to its symbol name.

    Used to recover selectors whose pointers prebinding moved outside the image.
    """
    return {
        symbol["address"]: symbol["name"]
        for symbol in document["symbols"]
        if symbol["section"] is not None
        and symbol["name"].startswith(("-[", "+["))
    }


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


def read_categories(reader, symtab_address):
    """Return the category records an ``objc_symtab`` defines."""
    class_count, category_count = reader.halves(symtab_address + 8, 2)
    definitions = reader.at(symtab_address + 12, class_count + category_count)
    categories = []
    for pointer in definitions[class_count:]:
        category_name, class_name, instance_methods, class_methods = reader.at(
            pointer, 4
        )
        categories.append({
            "name": reader.cstring(category_name),
            "class": reader.cstring(class_name),
            "instance_methods": reader.method_list(instance_methods),
            "class_methods": reader.method_list(class_methods),
        })
    return categories


def read_modules_from_sections(payload, sections, endianness, method_names=None):
    """Return ``{module name: abi-v1 document}`` for an image's ``__OBJC``."""
    reader = ObjcReader(payload, sections, endianness, method_names)
    info = next(
        (s for s in sections if s["name"] == "__OBJC,__module_info" and s.get("size")),
        None,
    )
    if info is None:
        raise ObjcAbiError("image has no __OBJC,__module_info section")

    modules = {}
    for index in range(info["size"] // 16):
        address = info["address"] + 16 * index
        _version, _size, name, symtab = reader.at(address, 4)
        module = reader.cstring(name)
        if module in modules:
            raise ObjcAbiError(f"__module_info names {module} more than once")
        modules[module] = {
            "schema_version": "abi-v1",
            "module": module,
            "classes": read_classes(reader, symtab),
            "categories": read_categories(reader, symtab),
            "text_symbols": [],
            "data_symbols": [],
        }
    return modules


def attach_symbols(modules, assignment, symbols):
    """Record each module's exported C symbols, split by segment.

    ``assignment`` maps a module name to the symbol names it owns. C functions
    carry no module attribution in the image (spec §2.1), so the assignment is
    declared from the module's public header rather than inferred.
    """
    by_name = {symbol["name"]: symbol for symbol in symbols}
    for module, names in assignment.items():
        if module not in modules:
            raise ObjcAbiError(f"assignment names unknown module {module}")
        text, data = [], []
        for name in names:
            symbol = by_name.get(name)
            if symbol is None:
                raise ObjcAbiError(f"image exports no symbol named {name}")
            section = symbol["section"]
            if section is None:
                raise ObjcAbiError(f"{name} is undefined in the image")
            bucket = text if section.startswith("__TEXT") else data
            bucket.append(name)
        modules[module]["text_symbols"] = sorted(text)
        modules[module]["data_symbols"] = sorted(data)


def read_modules(path):
    """Return ``{module name: abi-v1 document}`` for an image on disk."""
    from .macho import load_image

    payload, document = load_image(path)
    return read_modules_from_sections(
        payload, document["sections"], document["input"]["endianness"],
        method_symbol_index(document),
    )
