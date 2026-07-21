from binrecon.cli import build_parser


def test_help_lists_all_commands():
    help_text = build_parser().format_help()

    for command in ("validate", "analyze", "consensus", "compare", "ledger"):
        assert command in help_text
