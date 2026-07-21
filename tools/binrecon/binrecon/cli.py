import argparse
import os
from pathlib import Path
import sys

from jsonschema import ValidationError

from binrecon.profile import load_profile


COMMANDS = ("validate", "analyze", "consensus", "compare", "ledger")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="binrecon")
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command in COMMANDS:
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("--profile", required=True)

    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "validate":
        try:
            profile = load_profile(Path(args.profile), os.environ)
        except (OSError, ValueError, ValidationError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1

        for label, identity in (
            ("reference", profile.reference_identity),
            ("rebuilt", profile.rebuilt_identity),
        ):
            print(
                f"{label} {identity.path} size={identity.size} "
                f"sha256={identity.sha256}"
            )
        return 0

    print(f"binrecon: command not implemented: {args.command}")
    return 2
