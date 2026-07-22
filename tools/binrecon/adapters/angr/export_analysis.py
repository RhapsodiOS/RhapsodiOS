"""Deterministic angr analysis exporter; safe to import without angr installed."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import sys


_MAX_FLAT_IMAGE = 64 * 1024 * 1024
_MAX_FUNCTIONS = 100_000
_MAX_BLOCKS = 1_000_000


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(prog="binrecon-angr-export", allow_abbrev=False)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--layout", required=True)
    parser.add_argument("--size", required=True, type=int)
    parser.add_argument("--sha256", required=True)
    values = list(sys.argv[1:] if argv is None else argv)
    for option in ("--input", "--output", "--config", "--layout", "--size", "--sha256"):
        if values.count(option) > 1:
            parser.error(f"duplicate option: {option}")
    result = parser.parse_args(values)
    if result.size < 0:
        parser.error("--size must be nonnegative")
    if len(result.sha256) != 64 or any(character not in "0123456789abcdefABCDEF" for character in result.sha256):
        parser.error("--sha256 must be exactly 64 hexadecimal characters")
    return result


def _loader_failure(error: BaseException) -> bool:
    module = type(error).__module__
    name = type(error).__name__.lower()
    return module.startswith("cle.") and ("error" in name or "compatib" in name)


def _flat_image(path: Path, layout: dict) -> tuple[io.BytesIO, int, int]:
    sections = [item for item in layout.get("sections", []) if item.get("size", 0)]
    if not sections:
        raise ValueError("flat fallback requires at least one declared region")
    base = min(item["address"] for item in sections)
    end = max(item["address"] + item["size"] for item in sections)
    if end < base or end - base > _MAX_FLAT_IMAGE:
        raise ValueError("flat fallback image exceeds 64 MiB bound")
    image = bytearray(end - base)
    source = path.read_bytes()
    for item in sorted(sections, key=lambda value: (value["address"], value.get("ordinal", 0))):
        start = item["address"] - base
        size = item["size"]
        if item.get("initialized", True):
            offset = item["offset"]
            if offset > len(source) or size > len(source) - offset:
                raise ValueError(f"section {item.get('name', '')!r} exceeds input")
            image[start:start + size] = source[offset:offset + size]
    entries = layout.get("entry_points", [])
    entry = entries[0] if entries else int(layout.get("image_base", base))
    return io.BytesIO(bytes(image)), base, entry


def load_project(angr_module, path: Path, layout: dict):
    """Try native CLE loading first, then a canonical region-only i386 blob."""
    try:
        return angr_module.Project(str(path), auto_load_libs=False)
    except Exception as error:
        if not _loader_failure(error):
            raise
    stream, base, entry = _flat_image(path, layout)
    return angr_module.Project(stream, main_opts={"backend": "blob", "arch": "x86",
        "base_addr": base, "entry_point": entry}, auto_load_libs=False)


def function_starts(layout: dict, canonical: dict) -> list[int]:
    return sorted(set(layout.get("entry_points", [])) |
                  {item["address"] for item in canonical.get("symbols", [])
                   if isinstance(item.get("address"), int)})


def _instruction(insn, relocation_indexes: list[int]) -> dict:
    operands = getattr(insn, "op_str", "") or ""
    return {"address": int(insn.address), "bytes": bytes(insn.bytes).hex().upper(),
            "mnemonic": insn.mnemonic or "", "operands": operands,
            "normalized_operands": operands, "relocations": relocation_indexes}


def export_cfg(project, layout: dict, canonical: dict) -> tuple[list[dict], dict, list[dict]]:
    starts = function_starts(layout, canonical)
    cfg_errors = []
    cfg = project.analyses.CFGFast(normalize=True, function_starts=starts,
        resolve_indirect_jumps=True)
    functions, references = [], []
    relocation_addresses = [item["address"] for item in canonical.get("relocations", [])]
    vex_summaries = []
    for index, function in enumerate(sorted(cfg.kb.functions.values(), key=lambda value: value.addr)):
        if index >= _MAX_FUNCTIONS:
            cfg_errors.append("function limit reached"); break
        try:
            blocks, instructions, calls = [], [], []
            function_blocks = sorted(function.blocks, key=lambda value: value.addr)
            if len(function_blocks) > _MAX_BLOCKS: raise ValueError("block limit reached")
            maximum_end = int(function.addr)
            for block in function_blocks:
                maximum_end = max(maximum_end, int(block.addr + block.size))
                successors = []
                node = cfg.model.get_any_node(block.addr)
                if node is not None:
                    for successor in cfg.model.get_successors(node):
                        jumpkind = cfg.model.get_edge_data(node, successor).get("jumpkind", "")
                        successors.append({"target": int(successor.addr), "kind": str(jumpkind)})
                blocks.append({"address": int(block.addr), "size": int(block.size),
                               "successors": sorted(successors, key=lambda x: (x["target"], x["kind"]))})
                counts = Counter(str(operation) for operation in block.vex.operations)
                statements = Counter(str(statement.tag) for statement in block.vex.statements)
                vex_summaries.append({"address": int(block.addr), "operations":
                    {key: counts[key] for key in sorted(counts)}, "statements":
                    {key: statements[key] for key in sorted(statements)}})
                for insn in block.capstone.insns:
                    begin, finish = int(insn.address), int(insn.address + insn.size)
                    links = [i for i, address in enumerate(relocation_addresses)
                             if begin <= address < finish]
                    instructions.append(_instruction(insn, links))
            for callsite in sorted(function.get_call_sites()):
                target = function.get_call_target(callsite)
                calls.append({"address": int(callsite),
                              "target": None if target is None else int(target), "name": None})
            names = sorted(set(filter(None, [getattr(function, "name", None)])))
            functions.append({"address": int(function.addr),
                "size": max(0, maximum_end - int(function.addr)), "names": names,
                "blocks": sorted(blocks, key=lambda x: (x["address"], x["size"])),
                "instructions": sorted(instructions, key=lambda x: (x["address"], x["bytes"])),
                "calls": sorted(calls, key=lambda x: (x["address"], -1 if x["target"] is None else x["target"])),
                "confidence": 1.0})
        except Exception as error:
            cfg_errors.append(f"0x{int(function.addr):X}: {type(error).__name__}: {str(error)[:160]}")
    return functions, {"errors": sorted(cfg_errors), "vex_blocks": sorted(vex_summaries,
        key=lambda x: x["address"])}, references


def unsupported_check(name: str, reason: str) -> dict:
    return {"name": name, "status": "unsupported", "reason": reason}


def classify_execution(states, errors, *, hit_limit: bool) -> dict:
    if hit_limit: return {"status": "limit-reached", "reason": "execution bound reached"}
    if errors: return {"status": "unsupported", "reason": str(errors[0])[:200]}
    if not states: return {"status": "unsupported", "reason": "no terminal states"}
    return {"status": "passed"}


def _resolve_function(project, value: str) -> int | None:
    try: return int(value, 0)
    except ValueError: pass
    symbol = project.loader.find_symbol(value)
    return None if symbol is None else int(symbol.rebased_addr)


def _counterexample(state, symbolic_bytes, expression=None, constraint=None) -> dict:
    witness = state.copy()
    if constraint is not None:
        witness.add_constraints(constraint)
    result = {"input_hex": bytes(witness.solver.eval(byte) for byte in symbolic_bytes).hex().upper()}
    if expression is not None: result["actual"] = int(witness.solver.eval(expression))
    return result


def run_symbolic_check(project, check: dict) -> dict:
    """Execute a schema-v1 check using cdecl arguments (input pointer, byte count).

    Symbolic bytes live at a fixed private address and are named by check and index.
    Every assertion is proved by asking whether its negation is satisfiable in each
    reachable terminal state; a satisfying model is a failure counterexample.
    """
    name = check["name"]
    address = _resolve_function(project, check["function"])
    if address is None: return unsupported_check(name, f"function {check['function']!r} not found")
    for hook in check.get("hooks", []):
        if hook["handler"] != "return-constant" or "returns" not in hook:
            return unsupported_check(name, f"unsupported hook handler {hook['handler']!r}")
    for assertion in check.get("assertions", []):
        if assertion["kind"] == "return-equivalent":
            return unsupported_check(name, "return-equivalent requires paired artifact orchestration")
    try:
        import angr
        import claripy
        options = {angr.options.ZERO_FILL_UNCONSTRAINED_MEMORY,
                   angr.options.ZERO_FILL_UNCONSTRAINED_REGISTERS}
        count = int(check.get("input_bytes", 0)); pointer = 0x7FFF0000
        symbolic = [claripy.BVS(f"{name}_input_{index:04d}", 8) for index in range(count)]
        state = project.factory.call_state(address, pointer, count, add_options=options)
        for index, byte in enumerate(symbolic): state.memory.store(pointer + index, byte)
        for register, value in sorted(check.get("registers", {}).items()):
            if not hasattr(state.regs, register): return unsupported_check(name, f"unknown register {register!r}")
            setattr(state.regs, register, value)
        for memory in check.get("memory", []): state.memory.store(memory["address"], bytes.fromhex(memory["bytes"]))
        installed = []
        def constant_procedure(return_value):
            class ReturnConstant(angr.SimProcedure):
                def run(self): return return_value
            return ReturnConstant()
        for hook in check.get("hooks", []):
            project.hook(hook["address"], constant_procedure(hook["returns"]))
            installed.append(hook["address"])
        manager = project.factory.simulation_manager(state)
        hit_limit = False
        for _ in range(check["max_steps"]):
            if len(manager.active) > check["max_active_states"]:
                hit_limit = True; break
            if not manager.active: break
            manager.step()
        if manager.active: hit_limit = True
        if len(manager.active) > check["max_active_states"]: hit_limit = True
        errors = [f"{type(item.error).__name__}: {str(item.error)[:160]}" for item in manager.errored]
        terminals = list(manager.deadended)
        classification = classify_execution(terminals, errors, hit_limit=hit_limit)
        result = {"name": name, **classification, "steps": min(check["max_steps"],
                  getattr(manager, "_binrecon_steps", check["max_steps"])),
                  "terminal_states": len(terminals)}
        if result["status"] != "passed": return result
        for terminal in terminals:
            for assertion in check.get("assertions", []):
                kind = assertion["kind"]
                if kind == "return-equals":
                    expression = terminal.regs.eax
                    negated = expression != assertion["value"]
                elif kind == "memory-equals":
                    expected = bytes.fromhex(assertion["bytes"])
                    expression = terminal.memory.load(assertion["address"], len(expected))
                    negated = expression != claripy.BVV(expected)
                else: return unsupported_check(name, f"unsupported assertion {kind!r}")
                if terminal.solver.satisfiable(extra_constraints=[negated]):
                    return {"name": name, "status": "failed", "reason": kind,
                            "counterexample": _counterexample(terminal, symbolic, expression, negated),
                            "terminal_states": len(terminals)}
        return result
    except Exception as error:
        return unsupported_check(name, f"{type(error).__name__}: {str(error)[:180]}")
    finally:
        for hooked in locals().get("installed", []):
            try: project.unhook(hooked)
            except Exception: pass


def _atomic_json(path: Path, document: dict) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".write", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(document, stream, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try: os.unlink(temporary)
        except FileNotFoundError: pass
        raise


def main(argv=None) -> int:
    arguments = parse_arguments(argv)
    try:
        import angr
        path = Path(arguments.input).resolve(strict=True)
        payload = path.read_bytes()
        digest = hashlib.sha256(payload).hexdigest().upper()
        if len(payload) != arguments.size or digest != arguments.sha256.upper():
            raise ValueError("input identity does not match command line")
        config = json.loads(Path(arguments.config).read_text(encoding="utf-8"))
        layout = json.loads(Path(arguments.layout).read_text(encoding="utf-8"))
        project = load_project(angr, path, layout)
        canonical = {"symbols": layout.get("symbols", []),
                     "relocations": layout.get("relocations", [])}
        functions, cfg, references = export_cfg(project, layout, canonical)
        checks = [run_symbolic_check(project, check)
                  for check in config["profile"].get("symbolic_checks", [])]
        document = {"schema_version": "analysis-v1", "input": {"path": str(path),
            "size": len(payload), "sha256": digest, "architecture": "i386", "endianness": "little"},
            "analyzer": {"name": "angr", "version": angr.__version__,
                         "invocation": "binrecon-angr-export"},
            "sections": sorted([{key: item[key] for key in ("name", "address", "offset", "size", "permissions", "sha256")}
                         for item in layout.get("sections", []) if item.get("sha256")],
                         key=lambda x: (x["address"], x["offset"], x["name"], x["size"])),
            "symbols": sorted(layout.get("symbols", []), key=lambda x: (x["address"], x["name"], x["binding"], x["section"] or "")),
            "relocations": sorted(layout.get("relocations", []), key=lambda x: (x["address"], x["kind"], x["target"] or "", x["addend"])),
            "functions": functions, "references": references, "imports": [], "strings": [],
            "extensions": {"angr": {"cfg": cfg, "symbolic_checks": checks,
                "loader": {"sections": [{"address": x["address"], "size": x["size"],
                    "permissions": x["permissions"], "initialized": x.get("initialized", True)}
                    for x in layout.get("sections", [])]}}}}
        _atomic_json(Path(arguments.output), document)
        return 0
    except Exception as error:
        print(f"binrecon-angr-export: {type(error).__name__}: {error}", file=__import__("sys").stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
