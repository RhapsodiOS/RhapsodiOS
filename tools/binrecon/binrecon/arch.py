"""Per-architecture facts shared by the Mach-O reader and the analyzer adapters."""

from dataclasses import dataclass
import struct


class ArchitectureError(ValueError):
    """Raised when an architecture is unknown or disagrees with the input."""


@dataclass(frozen=True)
class MachOLayouts:
    """Mach-O on-disk structures in one architecture's byte order."""

    header: struct.Struct
    load_command: struct.Struct
    segment_command: struct.Struct
    section: struct.Struct
    symtab_command: struct.Struct
    nlist: struct.Struct
    relocation_info: struct.Struct


def _layouts(prefix: str) -> MachOLayouts:
    return MachOLayouts(
        header=struct.Struct(f"{prefix}7I"),
        load_command=struct.Struct(f"{prefix}2I"),
        segment_command=struct.Struct(f"{prefix}II16sIIIIiiII"),
        section=struct.Struct(f"{prefix}16s16sIIIIIIIII"),
        symtab_command=struct.Struct(f"{prefix}6I"),
        nlist=struct.Struct(f"{prefix}IBBHI"),
        relocation_info=struct.Struct(f"{prefix}iI"),
    )


@dataclass(frozen=True)
class Architecture:
    """Everything binrecon needs to know that varies by architecture."""

    name: str
    endianness: str
    struct_prefix: str
    cpu_type: int
    ida_processor: str
    relocation_decoder: str
    layouts: MachOLayouts


I386 = Architecture(
    name="i386",
    endianness="little",
    struct_prefix="<",
    cpu_type=7,
    ida_processor="metapc",
    relocation_decoder="i386",
    layouts=_layouts("<"),
)

PPC = Architecture(
    name="ppc",
    endianness="big",
    struct_prefix=">",
    cpu_type=18,
    ida_processor="ppc",
    relocation_decoder="ppc",
    layouts=_layouts(">"),
)

_SUPPORTED = (I386, PPC)
_BY_NAME = {architecture.name: architecture for architecture in _SUPPORTED}
_BY_CPU_TYPE = {architecture.cpu_type: architecture for architecture in _SUPPORTED}


def architecture_for_name(name: str) -> Architecture:
    """Return the descriptor a profile's ``architecture`` string names."""
    try:
        return _BY_NAME[name]
    except (KeyError, TypeError):
        supported = ", ".join(sorted(_BY_NAME))
        raise ArchitectureError(
            f"unsupported architecture {name!r}; expected one of {supported}"
        ) from None


def architecture_for_cpu_type(cpu_type: int, endianness: str) -> Architecture:
    """Return the descriptor for a Mach-O CPU type read in a given byte order."""
    architecture = _BY_CPU_TYPE.get(cpu_type)
    if architecture is None or architecture.endianness != endianness:
        raise ArchitectureError(
            f"unsupported Mach-O CPU type {cpu_type} read as {endianness}-endian; "
            "expected i386 (7, little-endian) or ppc (18, big-endian)"
        )
    return architecture
