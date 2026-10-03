# drvATIMach64 divergences and decisions

## Reference-only baseline

- Stock BinRecon/IDA 9.4 analysis is complete and reports 52 functions. Its normalized-function acceptance is false because there is no rebuilt artifact.
- Reviewed IDA export corrects the two omitted assembly functions by exact symbols, decodes complete far-transfer instructions at `0x273d` and `0x2811`, and records exclusive ends `0x2755` and `0x2883`. The corrected export contains 54 functions.
- No reference/rebuilt parity conclusion is available yet.
- The current source skeleton does not match the recovered `ATI` class/category symbols; initial source mapping therefore remains unresolved and is not counted as implementation coverage.
- No compatible hardware or ROM execution has been performed.
