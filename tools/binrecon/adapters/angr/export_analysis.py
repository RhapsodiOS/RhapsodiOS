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
_MAX_CHECKS = 128
_MAX_INPUT_BYTES = 256
_MAX_TOTAL_INPUT_BYTES = 4096
_MAX_MEMORY_SETUP = 64 * 1024
_MAX_REGISTERS = 64
_MAX_HOOKS = 64
_MAX_ACTIVE_STATES = 128
_MAX_STEPS = 10_000
_MAX_ASSERTIONS = 64
_MAX_PROOF_QUERIES = 1024
_SOLVER_TIMEOUT_MS = 2_000


class ProofLimit(RuntimeError):
    pass


def _limit_error(check: dict) -> str | None:
    if check.get("input_bytes", 0) > _MAX_INPUT_BYTES: return "input_bytes resource limit exceeded"
    if check.get("max_active_states", 0) > _MAX_ACTIVE_STATES: return "active-state resource limit exceeded"
    if check.get("max_steps", 0) > _MAX_STEPS: return "step resource limit exceeded"
    if len(check.get("hooks", [])) > _MAX_HOOKS: return "hook resource limit exceeded"
    if len(check.get("registers", {})) > _MAX_REGISTERS: return "register setup resource limit exceeded"
    if len(check.get("assertions", [])) > _MAX_ASSERTIONS: return "assertion resource limit exceeded"
    if sum(len(item["bytes"]) // 2 for item in check.get("memory", [])) > _MAX_MEMORY_SETUP:
        return "memory setup resource limit exceeded"
    addresses = [item["address"] for item in check.get("hooks", [])]
    if len(addresses) != len(set(addresses)): return "duplicate hook address"
    return None


def _validate_check_set(checks: list[dict]) -> None:
    if len(checks) > _MAX_CHECKS: raise ValueError("symbolic check count resource limit exceeded")
    if sum(check.get("input_bytes", 0) for check in checks) > _MAX_TOTAL_INPUT_BYTES:
        raise ValueError("total symbolic input resource limit exceeded")
    for check in checks:
        error = _limit_error(check)
        if error: raise ValueError(f"symbolic check {check.get('name', '')!r}: {error}")


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


def build_region_stream(path: Path, layout: dict) -> tuple[io.BytesIO, list[tuple[int, int, int]]]:
    sections = [item for item in layout.get("sections", []) if item.get("size", 0)]
    if not sections:
        raise ValueError("flat fallback requires at least one declared region")
    ordered = sorted(sections, key=lambda value: (value["address"], value.get("ordinal", 0)))
    previous_end = -1
    if sum(item["size"] for item in ordered) > _MAX_FLAT_IMAGE:
        raise ValueError("flat fallback mapped content exceeds 64 MiB bound")
    source = path.read_bytes()
    packed = bytearray()
    segments = []
    for item in ordered:
        if item["address"] < previous_end:
            raise ValueError("flat fallback regions overlap")
        size = item["size"]
        file_offset = len(packed)
        if item.get("initialized", True):
            offset = item["offset"]
            if offset > len(source) or size > len(source) - offset:
                raise ValueError(f"section {item.get('name', '')!r} exceeds input")
            packed.extend(source[offset:offset + size])
        else:
            packed.extend(b"\0" * size)
        segments.append((file_offset, item["address"], size))
        previous_end = item["address"] + size
    return io.BytesIO(bytes(packed)), segments


def _flat_image(path: Path, layout: dict) -> tuple[io.BytesIO, int, int, list[tuple[int, int, int]]]:
    stream, segments = build_region_stream(path, layout)
    base = int(layout.get("image_base", min(address for _, address, _ in segments)))
    entries = layout.get("entry_points", [])
    entry = entries[0] if entries else int(layout.get("image_base", base))
    return stream, base, entry, segments


def load_project(angr_module, path: Path, layout: dict):
    """Try native CLE loading first, then a canonical region-only i386 blob."""
    try:
        return angr_module.Project(str(path), auto_load_libs=False)
    except Exception as error:
        if not _loader_failure(error):
            raise
    stream, base, entry, segments = _flat_image(path, layout)
    return angr_module.Project(stream, main_opts={"backend": "blob", "arch": "x86",
        "base_addr": base, "entry_point": entry, "segments": segments}, auto_load_libs=False)


def function_starts(layout: dict, canonical: dict) -> list[int]:
    return sorted(set(layout.get("entry_points", [])) |
                  {item["address"] for item in canonical.get("symbols", [])
                   if isinstance(item.get("address"), int)})


def _instruction(insn, relocation_indexes: list[int]) -> dict:
    operands = getattr(insn, "op_str", "") or ""
    return {"address": int(insn.address), "bytes": bytes(insn.bytes).hex().upper(),
            "mnemonic": insn.mnemonic or "", "operands": operands,
            "normalized_operands": operands, "relocations": relocation_indexes}


def _instruction_operand_metadata(insn) -> dict:
    from capstone import CS_OP_IMM, CS_OP_MEM, CS_OP_REG

    result = []
    for index, operand in enumerate(insn.insn.operands):
        if operand.type == CS_OP_REG:
            item = {"index": index, "kind": "register"}
        elif operand.type == CS_OP_IMM:
            item = {"index": index, "kind": "immediate"}
            immediate_width = int(insn.insn.imm_size)
            if immediate_width:
                if immediate_width not in {1, 2, 4}:
                    raise RuntimeError("unsupported immediate field width")
                item.update({"resolved_address": int(operand.imm),
                             "field_offset": int(insn.insn.imm_offset),
                             "field_width": immediate_width})
        elif operand.type == CS_OP_MEM:
            item = {"index": index, "kind": "memory"}
            memory = operand.mem
            displacement_width = int(insn.insn.disp_size)
            if displacement_width:
                if displacement_width not in {1, 2, 4}:
                    raise RuntimeError("unsupported displacement field width")
                displacement = int(memory.disp) & ((1 << (8 * displacement_width)) - 1)
                item.update({"encoded_address": displacement,
                             "field_offset": int(insn.insn.disp_offset),
                             "field_width": displacement_width})
        else:
            item = {"index": index, "kind": "other"}
        result.append(item)
    return {"address": int(insn.address), "operands": result}


def export_cfg(project, layout: dict, canonical: dict) -> tuple[list[dict], dict, list[dict]]:
    starts = function_starts(layout, canonical)
    cfg_errors = []
    executable = [(item["address"], item["address"] + item["size"])
                  for item in layout.get("sections", [])
                  if "x" in item.get("permissions", "") and item.get("size", 0)]
    cfg = project.analyses.CFGFast(normalize=True, function_starts=starts,
        resolve_indirect_jumps=True, regions=executable or None,
        exclude_sparse_regions=False, skip_unmapped_addrs=True)
    functions, raw_references = [], []
    relocation_addresses = [item["address"] for item in canonical.get("relocations", [])]
    vex_summaries = []
    operand_metadata = {}
    def in_executable(address, size=1):
        return not executable or any(start <= address and address + size <= end
                                     for start, end in executable)
    for index, function in enumerate(sorted(cfg.kb.functions.values(), key=lambda value: value.addr)):
        if index >= _MAX_FUNCTIONS:
            cfg_errors.append("function limit reached"); break
        try:
            if not in_executable(int(function.addr)):
                continue
            blocks, instructions, calls = [], [], []
            function_blocks = [block for block in sorted(function.blocks, key=lambda value: value.addr)
                               if in_executable(int(block.addr), int(block.size))]
            if len(function_blocks) > _MAX_BLOCKS: raise ValueError("block limit reached")
            maximum_end = int(function.addr)
            for block in function_blocks:
                maximum_end = max(maximum_end, int(block.addr + block.size))
                successors = []
                node = cfg.model.get_any_node(block.addr)
                if node is not None:
                    for successor in cfg.model.get_successors(node):
                        edge = cfg.graph.get_edge_data(node, successor) or {}
                        jumpkind = edge.get("jumpkind", "")
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
                    metadata = _instruction_operand_metadata(insn)
                    previous = operand_metadata.get(metadata["address"])
                    if previous is not None and previous != metadata:
                        raise ValueError("conflicting Capstone operand metadata")
                    operand_metadata[metadata["address"]] = metadata
                if block.capstone.insns:
                    source_address = int(block.capstone.insns[-1].address)
                    for successor in successors:
                        kind = "control-call" if "Call" in successor["kind"] else "control-branch"
                        raw_references.append((source_address, successor["target"], kind))
                current_instruction = int(block.addr)
                for statement in block.vex.statements:
                    if statement.tag == "Ist_IMark":
                        current_instruction = int(statement.addr)
                    expression = None
                    kind = None
                    if statement.tag == "Ist_Store":
                        expression, kind = statement.addr, "data-write"
                    elif statement.tag == "Ist_WrTmp" and getattr(statement.data, "tag", "") == "Iex_Load":
                        expression, kind = statement.data.addr, "data-read"
                    if expression is not None and getattr(expression, "tag", "") == "Iex_Const":
                        target = int(expression.con.value)
                        if target in project.loader.memory:
                            raw_references.append((current_instruction, target, kind))
            blocks_by_address = {int(block.addr): block for block in function_blocks}
            for callsite in sorted(function.get_call_sites()):
                call_block = blocks_by_address.get(int(callsite))
                if call_block is None or not call_block.capstone.insns:
                    cfg_errors.append(f"0x{int(callsite):X}: callsite block is unavailable")
                    continue
                call_instruction = call_block.capstone.insns[-1]
                if not (call_instruction.mnemonic or "").lower().startswith("call"):
                    cfg_errors.append(f"0x{int(callsite):X}: callsite does not end in a call")
                    continue
                call_address = int(call_instruction.address)
                target = function.get_call_target(callsite)
                target_value = None if target is None else int(target)
                target_function = cfg.kb.functions.get(target_value) if target_value is not None else None
                calls.append({"address": call_address,
                              "target": target_value,
                              "name": getattr(target_function, "name", None)})
                if target_value is not None:
                    raw_references.append((call_address, target_value, "control-call"))
            names = sorted(set(filter(None, [getattr(function, "name", None)])))
            functions.append({"address": int(function.addr),
                "size": max(0, maximum_end - int(function.addr)), "names": names,
                "blocks": sorted(blocks, key=lambda x: (x["address"], x["size"])),
                "instructions": sorted(instructions, key=lambda x: (x["address"], x["bytes"])),
                "calls": sorted(calls, key=lambda x: (x["address"], -1 if x["target"] is None else x["target"])),
                "confidence": 1.0})
        except Exception as error:
            cfg_errors.append(f"0x{int(function.addr):X}: {type(error).__name__}: {str(error)[:160]}")
    references = [{"address": address, "target": target, "kind": kind}
                  for address, target, kind in sorted(set(raw_references),
                      key=lambda item: (item[0], item[1], item[2]))]
    indexes = {}
    for index, reference in enumerate(references):
        indexes.setdefault(str(reference["address"]), []).append(index)
    instruction_indexes = [{"address": int(address), "references": indexes[address]}
                           for address in sorted(indexes, key=int)]
    return functions, {"errors": sorted(cfg_errors), "vex_blocks": sorted(vex_summaries,
        key=lambda x: x["address"]),
        "instruction_reference_indexes": instruction_indexes,
        "instruction_operand_metadata": [operand_metadata[address]
            for address in sorted(operand_metadata)]}, references


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


def _new_solver(constraints=()):
    import claripy
    solver = claripy.Solver(timeout=_SOLVER_TIMEOUT_MS)
    if constraints: solver.add(*constraints)
    return solver


def _lexicographic_model(solver, symbolic_bytes, expressions, constraint):
    import claripy
    combined = _new_solver(solver.constraints)
    combined.add(constraint)
    try:
        for byte in symbolic_bytes:
            minimum = combined.min(byte)
            combined.add(byte == minimum)
        return combined.batch_eval([*symbolic_bytes, *expressions], 1)[0]
    except claripy.errors.ClaripySolverInterruptError as error:
        raise ProofLimit("solver query timed out") from error


def _counterexample(state, symbolic_bytes, expression=None, constraint=None) -> dict:
    expressions = [] if expression is None else [expression]
    values = _lexicographic_model(state.solver, symbolic_bytes, expressions, constraint)
    result = {"input_hex": bytes(values[:len(symbolic_bytes)]).hex().upper()}
    if expression is not None: result["actual"] = int(values[-1])
    return result


def _execute_symbolically(project, check: dict, symbolic_prefix: str) -> dict:
    import angr
    import claripy
    name = check["name"]
    address = _resolve_function(project, check["function"])
    if address is None:
        return {"status": "unsupported", "reason": f"function {check['function']!r} not found"}
    for hook in check.get("hooks", []):
        if hook["handler"] != "return-constant" or "returns" not in hook:
            return {"status": "unsupported", "reason": f"unsupported hook handler {hook['handler']!r}"}
    limit = _limit_error(check)
    if limit: return {"status": "unsupported", "reason": limit}
    options = {angr.options.SYMBOL_FILL_UNCONSTRAINED_MEMORY,
               angr.options.SYMBOL_FILL_UNCONSTRAINED_REGISTERS}
    count = int(check.get("input_bytes", 0)); pointer = 0x7FFF0000
    symbolic = [claripy.BVS(f"{symbolic_prefix}_{index:04d}", 8, explicit_name=True)
                for index in range(count)]
    state = project.factory.call_state(address, pointer, count, add_options=options)
    for index, byte in enumerate(symbolic): state.memory.store(pointer + index, byte)
    for register, value in sorted(check.get("registers", {}).items()):
        if not hasattr(state.regs, register):
            return {"status": "unsupported", "reason": f"unknown register {register!r}"}
        setattr(state.regs, register, value)
    for memory in check.get("memory", []):
        state.memory.store(memory["address"], bytes.fromhex(memory["bytes"]))
    installed = []
    def constant_procedure(return_value):
        class ReturnConstant(angr.SimProcedure):
            def run(self): return return_value
        return ReturnConstant()
    try:
        for hook in check.get("hooks", []):
            address = hook["address"]
            prior = project.hooked_by(address) if project.is_hooked(address) else None
            project.hook(address, constant_procedure(hook["returns"]), replace=True)
            installed.append((address, prior))
        manager = project.factory.simulation_manager(state)
        steps = 0
        state_cap = False
        while manager.active and steps < check["max_steps"]:
            if len(manager.active) > check["max_active_states"]:
                state_cap = True; break
            manager.step(); steps += 1
            if len(manager.active) > check["max_active_states"]:
                state_cap = True; break
        errors = sorted(f"{type(item.error).__name__}: {str(item.error)[:160]}"
                        for item in manager.errored)
        unconstrained = list(manager.stashes.get("unconstrained", []))
        obstructed = []
        for stash in ("stashed", "pruned", "avoided"):
            if manager.stashes.get(stash): obstructed.append(stash)
        base = {"steps": steps, "terminal_states": len(manager.deadended),
                "discarded_unsat_states": len(manager.stashes.get("unsat", [])),
                "states": list(manager.deadended), "symbolic": symbolic}
        if errors:
            return {**base, "status": "unsupported", "reason": errors[0]}
        if unconstrained:
            return {**base, "status": "unsupported",
                    "reason": f"unconstrained states: {len(unconstrained)}"}
        if obstructed:
            return {**base, "status": "unsupported",
                    "reason": "nonterminal stashes: " + ",".join(obstructed)}
        if state_cap:
            return {**base, "status": "limit-reached", "reason": "active state cap reached"}
        if manager.active:
            return {**base, "status": "limit-reached", "reason": "maximum steps reached"}
        if not manager.deadended:
            return {**base, "status": "unsupported", "reason": "no terminal states"}
        return {**base, "status": "passed"}
    finally:
        for hooked, prior in reversed(installed):
            try:
                project.unhook(hooked)
                if prior is not None:
                    project.hook(hooked, prior, length=getattr(prior, "length", 0), replace=True)
            except Exception: pass


def _undeclared_variables(execution: dict, expressions=()) -> list[str]:
    allowed = set().union(*(item.variables for item in execution.get("symbolic", [])))
    observed = set()
    for state in execution.get("states", []):
        for constraint in state.solver.constraints: observed.update(constraint.variables)
    for expression in expressions: observed.update(getattr(expression, "variables", set()))
    return sorted(observed - allowed)


def run_symbolic_check(project, check: dict) -> dict:
    """Execute a schema-v1 check using cdecl arguments (input pointer, byte count).

    Symbolic bytes live at a fixed private address and are named by check and index.
    Every assertion is proved by asking whether its negation is satisfiable in each
    reachable terminal state; a satisfying model is a failure counterexample.
    """
    name = check["name"]
    limit = _limit_error(check)
    if limit: return unsupported_check(name, limit)
    for assertion in check.get("assertions", []):
        if assertion["kind"] == "return-equivalent":
            return unsupported_check(name, "return-equivalent requires paired artifact orchestration")
    try:
        import claripy
        execution = _execute_symbolically(project, check, f"{name}_input")
        result = {key: value for key, value in execution.items()
                  if key not in ("states", "symbolic")}
        result["name"] = name
        if result["status"] != "passed": return result
        terminals, symbolic = execution["states"], execution["symbolic"]
        undeclared_paths = _undeclared_variables(execution)
        if undeclared_paths:
            return unsupported_check(name, "undeclared symbolic variables: " + ",".join(undeclared_paths))
        query_count = 0
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
                undeclared = _undeclared_variables(execution, [expression, negated])
                if undeclared:
                    return unsupported_check(name, "undeclared symbolic variables: " + ",".join(undeclared))
                query_count += 1
                if query_count > _MAX_PROOF_QUERIES:
                    return {"name": name, "status": "limit-reached", "reason": "proof query limit reached"}
                solver = _new_solver(terminal.solver.constraints)
                try: satisfiable = solver.satisfiable(extra_constraints=[negated])
                except claripy.errors.ClaripySolverInterruptError:
                    return {"name": name, "status": "limit-reached", "reason": "solver query timed out"}
                if satisfiable:
                    if query_count + len(symbolic) + 1 > _MAX_PROOF_QUERIES:
                        return {"name": name, "status": "limit-reached", "reason": "witness query limit reached"}
                    return {"name": name, "status": "failed", "reason": kind,
                            "counterexample": _counterexample(terminal, symbolic, expression, negated),
                            "terminal_states": len(terminals)}
        return result
    except ProofLimit as error:
        return {"name": name, "status": "limit-reached", "reason": str(error)}
    except Exception as error:
        return unsupported_check(name, f"{type(error).__name__}: {str(error)[:180]}")


def run_equivalent_check(reference_project, rebuilt_project, check: dict) -> dict:
    name = check["name"]
    limit = _limit_error(check)
    if limit: return unsupported_check(name, limit)
    try:
        import claripy
        prefix = f"{name}_joint_input"
        reference = _execute_symbolically(reference_project, check, prefix)
        rebuilt = _execute_symbolically(rebuilt_project, check, prefix)
        steps = {"reference": reference.get("steps", 0), "rebuilt": rebuilt.get("steps", 0)}
        for side, execution in (("reference", reference), ("rebuilt", rebuilt)):
            if execution["status"] != "passed":
                return {"name": name, "status": execution["status"], "steps": steps,
                        "reason": f"{side}: {execution.get('reason', execution['status'])}"}
        symbolic = reference["symbolic"]
        query_count = 0
        for reference_state in reference["states"]:
            for rebuilt_state in rebuilt["states"]:
                undeclared = _undeclared_variables(reference, [reference_state.regs.eax])
                undeclared += _undeclared_variables(rebuilt, [rebuilt_state.regs.eax])
                if undeclared:
                    return unsupported_check(name, "undeclared symbolic variables: " + ",".join(sorted(set(undeclared))))
                solver = _new_solver([*reference_state.solver.constraints,
                                      *rebuilt_state.solver.constraints])
                disequality = reference_state.regs.eax != rebuilt_state.regs.eax
                query_count += 1
                if query_count > _MAX_PROOF_QUERIES:
                    return {"name": name, "status": "limit-reached", "reason": "proof query limit reached"}
                try: satisfiable = solver.satisfiable(extra_constraints=[disequality])
                except claripy.errors.ClaripySolverInterruptError:
                    return {"name": name, "status": "limit-reached", "reason": "solver query timed out"}
                if satisfiable:
                    if query_count + len(symbolic) + 1 > _MAX_PROOF_QUERIES:
                        return {"name": name, "status": "limit-reached", "reason": "witness query limit reached"}
                    values = _lexicographic_model(solver, symbolic,
                        [reference_state.regs.eax, rebuilt_state.regs.eax], disequality)
                    return {"name": name, "status": "failed", "reason": "return-equivalent",
                        "steps": steps, "counterexample": {
                            "input_hex": bytes(values[:len(symbolic)]).hex().upper(),
                            "reference_return": int(values[-2]), "rebuilt_return": int(values[-1])}}
        return {"name": name, "status": "passed", "steps": steps,
                "terminal_states": {"reference": len(reference["states"]),
                                    "rebuilt": len(rebuilt["states"])}}
    except ProofLimit as error:
        return {"name": name, "status": "limit-reached", "reason": str(error)}
    except Exception as error:
        return unsupported_check(name, f"{type(error).__name__}: {str(error)[:180]}")


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
        profile_checks = config["profile"].get("symbolic_checks", [])
        _validate_check_set(profile_checks)
        project = load_project(angr, path, layout)
        canonical = {"symbols": layout.get("symbols", []),
                     "relocations": layout.get("relocations", [])}
        functions, cfg, references = export_cfg(project, layout, canonical)
        needs_peer = any(any(assertion["kind"] == "return-equivalent"
                             for assertion in check.get("assertions", []))
                         for check in profile_checks)
        peer_project = None
        if needs_peer:
            peer = config["peer_input"]
            peer_path = Path(peer["path"]).resolve(strict=True)
            peer_payload = peer_path.read_bytes()
            peer_digest = hashlib.sha256(peer_payload).hexdigest().upper()
            if len(peer_payload) != peer["size"] or peer_digest != peer["sha256"].upper():
                raise ValueError("peer input identity does not match configuration")
            peer_project = load_project(angr, peer_path, config["peer_layout"])
        checks = []
        for check in profile_checks:
            equivalence = [assertion for assertion in check.get("assertions", [])
                           if assertion["kind"] == "return-equivalent"]
            if equivalence:
                if len(equivalence) != len(check.get("assertions", [])):
                    checks.append(unsupported_check(check["name"],
                        "mixed return-equivalent and local assertions are unsupported"))
                    continue
                if config["artifact"] == "reference":
                    checks.append(run_equivalent_check(project, peer_project, check))
                else:
                    checks.append(run_equivalent_check(peer_project, project, check))
            else:
                checks.append(run_symbolic_check(project, check))
        document = {"schema_version": "analysis-v1", "input": {"path": str(path),
            "size": len(payload), "sha256": digest, "architecture": "i386", "endianness": "little"},
            "analyzer": {"name": "angr", "version": angr.__version__,
                         "invocation": "binrecon-angr-export"},
            "sections": sorted([{key: item[key] for key in ("name", "address", "offset", "size", "permissions", "sha256")}
                         for item in layout.get("sections", [])],
                         key=lambda x: (x["address"], x["offset"], x["name"], x["size"])),
            "symbols": sorted(layout.get("symbols", []), key=lambda x: (x["address"], x["name"], x["binding"], x["section"] or "")),
            "relocations": sorted(layout.get("relocations", []), key=lambda x: (x["address"], x["kind"], x["target"] or "", x["addend"])),
            "functions": functions, "references": references, "imports": [], "strings": [],
            "extensions": {"angr": {"cfg": cfg, "symbolic_checks": checks,
                "relocations": layout.get("relocation_metadata", []),
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
