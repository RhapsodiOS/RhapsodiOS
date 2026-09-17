# BOM-Free Remote Script Transport Design

## Problem

`Invoke-RhapSshScript` and `Invoke-RhapSshCapture` write normalized shell text through `Process.StandardInput`. Windows PowerShell 5.1 constructs that implicit `StreamWriter` with a UTF-8 encoding whose preamble is `EF BB BF`. The Xserve's `/bin/sh` therefore sees the first command as `\uFEFFset` rather than `set`. Because `set -e` is the rejected command, later successful commands can leave SSH with status zero and make a canonical build look green while errexit was disabled.

## Transport contract

- Encode process-backed SSH stdin as strict UTF-8 with no BOM by using `System.Text.UTF8Encoding($false, $true)` while PowerShell constructs the process-owned stdin `StreamWriter`. PowerShell 5.1 lacks `ProcessStartInfo.StandardInputEncoding`, so the helper temporarily scopes `Console.InputEncoding` around process start and immediate writer acquisition, then restores it before any payload I/O.
- Apply the same encoding boundary to streaming scripts, buffered scripts, and captured scripts.
- Preserve CRLF/CR normalization to LF and exactly one final LF.
- Preserve the existing asynchronous streaming writer/reader ordering, output observation, cleanup, and SSH exit-code propagation.
- Preserve the invoker seam as a string-level seam; raw-byte tests exercise the real process path.
- Reject malformed UTF-16 locally instead of silently writing replacement bytes. Valid Unicode is encoded as UTF-8; ASCII shell scripts remain byte-for-byte ASCII.

## Verification

A hermetic native stdin-capture fixture will record raw bytes without invoking SSH. Tests will cover generated preflight, fresh, and phase scripts through the streaming and buffered paths, the profile-read command through capture, malformed surrogate rejection, and restoration of the host console encoding. A copied canonical `build-src.ps1 -Rbuild` entry point will run under PowerShell 5.1 with `-NoProfile -File` and fake SSH so a host-default encoding cannot make the in-process test misleading. No remote build or bootstrap is part of this change.
