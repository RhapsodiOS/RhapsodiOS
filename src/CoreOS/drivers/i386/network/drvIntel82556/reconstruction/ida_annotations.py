"""Apply reviewed import types/source links to the reference IDA database.

Run in IDA's Python context, with the ida-domain Database in ``db``:
    import runpy
    helpers = runpy.run_path('/path/to/reconstruction/ida_annotations.py')
    helpers['annotate'](db, '/path/to/ignored/ida-reviewed.json')

This changes analysis metadata only. It neither patches bytes nor relaxes the
independent BinRecon comparison. Input addresses are specific to this reference.
"""
import json
from pathlib import Path

REFERENCE_SHA256 = "C26B34F0A07346F20C1D51795C601BED436CF3BE20E0AB6882E98C9114508B72"
RECON = Path(__file__).resolve().parent

# DriverKit generalFuncs.h/kernelDriver.h and kernel bsd/net/netbuf.h.
# Opaque kernel pointers and 32-bit vm_task_t/IOReturn use their i386 ABI forms.
IMPORTS = {
    0xA138: ("_IOVmTaskSelf", "unsigned int __cdecl IOVmTaskSelf(void);"),
    0xA12C: ("_IOPhysicalFromVirtual", "int __cdecl IOPhysicalFromVirtual(unsigned int task, unsigned int address, unsigned int *physical);"),
    0xA118: ("_IODelay", "void __cdecl IODelay(unsigned int microseconds);"),
    0xA134: ("_IOSleep", "void __cdecl IOSleep(unsigned int milliseconds);"),
    0xA120: ("_IOLog", "void __cdecl IOLog(const char *format, ...);"),
    0xA128: ("_IOPanic", "void __cdecl IOPanic(const char *message);"),
    0xA124: ("_IOMalloc", "void *__cdecl IOMalloc(int size);"),
    0xA11C: ("_IOFree", "void __cdecl IOFree(void *address, int size);"),
    0xA13C: ("_bcopy", "void __cdecl bcopy(const void *source, void *destination, unsigned int size);"),
    0xA150: ("_nb_map", "char *__cdecl nb_map(void *buffer);"),
    0xA15C: ("_nb_size", "unsigned int __cdecl nb_size(void *buffer);"),
    0xA14C: ("_nb_free", "void __cdecl nb_free(void *buffer);"),
    0xA144: ("_nb_alloc", "void *__cdecl nb_alloc(unsigned int size);"),
    0xA154: ("_nb_shrink_bot", "int __cdecl nb_shrink_bot(void *buffer, unsigned int size);"),
    0xA158: ("_nb_shrink_top", "int __cdecl nb_shrink_top(void *buffer, unsigned int size);"),
}


def annotate(db, output):
    import ida_auto
    import ida_funcs
    import ida_hexrays
    import ida_nalt
    from ida_domain.types import TypeApplyFlags

    digest = ida_nalt.retrieve_input_file_sha256()
    assert digest and digest.hex().upper() == REFERENCE_SHA256, "wrong reference database"
    for address, (name, declaration) in IMPORTS.items():
        assert db.names.get_at(address) == name, "reference import address changed"
        assert db.types.apply_declaration_at(address, declaration, TypeApplyFlags.DEFINITE)
    # Recompute SP after correcting nb_map's cdecl signature. In the uncorrected
    # database, 0x2a97 was inferred to purge 24 stack bytes, hiding bcopy arguments.
    ida_funcs.reanalyze_function(ida_funcs.get_func(0x293C))
    ida_auto.auto_wait()
    mapping = json.loads((RECON / "source-map.json").read_text(encoding="utf-8"))
    assert len(mapping["mapped"]) == 92
    for entry in mapping["mapped"]:
        function = db.functions.get_at(entry["address"])
        assert function is not None and function.start_ea == entry["address"]
        comment = "Reconstruction: {}:{}\nReviewed against reference assembly; binary equivalence unproved.".format(
            entry["source_path"], entry["source_line"])
        previous = db.functions.get_comment(function)
        if comment not in previous:
            assert db.functions.set_comment(function, (previous + "\n" + comment).strip())
    ida_hexrays.clear_cached_cfuncs()
    rows = []
    for entry in mapping["mapped"]:
        function = db.functions.get_at(entry["address"])
        rows.append({
            "address": entry["address"],
            "names": entry["reference_names"],
            "source_path": entry["source_path"],
            "source_line": entry["source_line"],
            "pseudocode": str(db.functions.get_pseudocode(function)),
        })
    Path(output).write_text(json.dumps({"reference_sha256": REFERENCE_SHA256,
        "decompiled": len(rows), "functions": rows}, indent=2) + "\n", encoding="utf-8")
    print("92/92 functions decompiled and annotated; save the IDA database to persist.")
