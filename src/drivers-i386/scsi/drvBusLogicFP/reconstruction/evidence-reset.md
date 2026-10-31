# Bus reset evidence

The bus reset path was checked against the `0x6774` IDA pseudocode and its I/O instruction order. It asserts the controller reset bit, waits through the timer handshake, clears pending SCSI state, resets target negotiation values, reinitializes each target entry, clears adapter queue/current-command state, and releases reset. `manager_reset_without_bus_interrupt` runs the manager reset path with scripted port reads and checks the complete register-trace termination.
