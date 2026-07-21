import argparse


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
    print(f"binrecon: command not implemented: {args.command}")
    return 2
