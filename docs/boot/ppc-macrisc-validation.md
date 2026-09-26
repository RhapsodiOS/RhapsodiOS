# PPC MacRISC Hardware Validation

Status: **not run.** The MacRISC platform path (plan
`docs/superpowers/plans/2026-08-01-ppc-macrisc-platform-support.md`, Tasks
1-10) is implemented and host-tested but has not been built for PPC or booted.
Fill this record from real boots only.

| Machine | Model | CPU | Mac-IO | Kernel hash | Result |
|---|---|---|---|---|---|
| Cube | PowerMac5,1 | | | | Not run |
| PowerBook G4 | PowerBook3,4 | | | | Not run |
| Xserve G4 DP | RackMac1,1 | | | | Not run |

For each machine record descriptor output, console, root device, shell result,
10-minute clock delta, disk stress, clean shutdown, and first failure line.
Boot from a temporary or dedicated disk, never a shared image.

## What to capture

- The discovery line printed by `configure_macrisc()`, for example
  `MacRISC: RackMac1,1 accepted: cpu=745x mac-io=KeyLargo`. The Cube must not
  print one: it stays on the Sawtooth route.
- A rejection prints `MacRISC: <model> rejected: ...` before the console is up
  and then panics with `Unsupported MacRISC platform`. If the screen shows
  nothing, record that and the last firmware output.
- Open Firmware values for the root `compatible`, `/cpus` (count,
  `cpu-version`, `clock-frequency`, `bus-frequency`, `timebase-frequency`),
  the `mac-io` node (`compatible`, `device-id`, `assigned-addresses`), its
  `interrupt-controller`, `via-pmu` or `via-cuda`, `escc-legacy`, the ATA
  nodes, `extint-gpio1`, and the root `nvram` node.
- Whether the ATA nodes carry `AAPL,interrupts`. Without it, DriverKit gives
  them no interrupts on this path; see the plan's known gaps.

## Results

No results yet.
