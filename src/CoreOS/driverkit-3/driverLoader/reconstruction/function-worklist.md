# driverLoader function worklist

Date: 2026-09-28

Rebuilt i386: `CFA1627DD7F44AF835D699FD50368B1885DAFDD9F2FCD5A71B508C36BF4B7C25`
Rebuilt ppc: `F08A579F376CDC99E2F68DEAE3E9E2C51D09E58E6564D13DB9496DDB4B1964EA`

Rows come from `binrecon function --list`, cheapest difference first. libDriver
functions are not listed: they are the i386 accept in divergences.md.

## i386

| Function | Group | diff (ref/new insns) | Ledger (pic_equal) |
|---|---|---|---|
| `__dyld_func_lookup` | crt | 0 (1/1) | assembly-matched (pic_equal) |
| `_print_string` | kl_com | 0 (6/6) | assembly-matched (pic_equal) |
| `dyld_stub_binding_helper` | crt | 0 (2/2) | assembly-matched (pic_equal) |
| `start` | crt | 0 (12/12) | assembly-matched (pic_equal) |
| `__call_mod_init_funcs` | crt | 1 (15/15) | assembly-matched (pic_equal) |
| `_kern_loader_status_port` | libkernload | 1 (24/24) | assembly-matched (pic_equal) |
| `__dyld_init_check` | crt | 2 (14/14) | intentional-mismatch (different) |
| `_kern_loader_look_up` | libkernload | 2 (15/15) | assembly-matched (pic_equal) |
| `_kern_loader_ping` | libkernload | 2 (29/29) | assembly-matched (pic_equal) |
| `_kl_com_error` | kl_com | 2 (14/14) | assembly-matched (pic_equal) |
| `_securityCheck` | owned | 3 (24/24) | assembly-matched (pic_equal) |
| `_ping` | kl_com | 4 (25/25) | assembly-matched (pic_equal) |
| `_kl_com_delete` | kl_com | 5 (37/37) | assembly-matched (pic_equal) |
| `_kl_com_unload` | kl_com | 5 (37/37) | assembly-matched (pic_equal) |
| `_kl_com_load` | kl_com | 6 (41/41) | assembly-matched (pic_equal) |
| `_kl_com_wait` | kl_com | 6 (32/32) | assembly-matched (pic_equal) |
| `_usage` | owned | 6 (28/28) | assembly-matched (pic_equal) |
| `_inquire` | owned | 8 (32/32) | assembly-matched (pic_equal) |
| `_kern_loader_reply_handler` | libkernload | 8 (67/67) | assembly-matched (pic_equal) |
| `_kl_com_get_state` | kl_com | 8 (56/56) | assembly-matched (pic_equal) |
| `_kl_com_add` | kl_com | 10 (51/51) | assembly-matched (pic_equal) |
| `_kern_loader_abort` | libkernload | 14 (69/69) | assembly-matched (pic_equal) |
| `_kern_loader_get_log` | libkernload | 14 (69/69) | assembly-matched (pic_equal) |
| `_kern_loader_load_server` | libkernload | 14 (74/74) | assembly-matched (pic_equal) |
| `_kern_loader_log_level` | libkernload | 14 (69/69) | assembly-matched (pic_equal) |
| `_kern_loader_add_server` | libkernload | 15 (79/79) | assembly-matched (pic_equal) |
| `_kern_loader_delete_server` | libkernload | 15 (79/79) | assembly-matched (pic_equal) |
| `_kern_loader_unload_server` | libkernload | 15 (79/79) | assembly-matched (pic_equal) |
| `_kern_loader_server_list` | libkernload | 16 (76/76) | assembly-matched (pic_equal) |
| `__start` | crt | 17 (67/67) | assembly-matched (pic_equal) |
| `_kern_loader_server_com_port` | libkernload | 20 (91/91) | assembly-matched (pic_equal) |
| `_kern_loader_server_task_port` | libkernload | 20 (91/91) | assembly-matched (pic_equal) |
| `_getInstanceFile` | owned | 21 (86/86) | assembly-matched (pic_equal) |
| `_processDriverList` | owned | 22 (62/65) | intentional-mismatch (different) |
| `_securityCheckDir` | owned | 32 (191/191) | assembly-matched (pic_equal) |
| `_prePostExec` | owned | 33 (128/128) | intentional-mismatch (different) |
| `_configDriver` | owned | 34 (176/176) | assembly-matched (pic_equal) |
| `_kl_com_log` | kl_com | 35 (129/129) | assembly-matched (pic_equal) |
| `_unloadDriver` | owned | 36 (172/172) | assembly-matched (pic_equal) |
| `_kern_loader_server_info` | libkernload | 37 (174/174) | assembly-matched (pic_equal) |
| `_kern_loader_server_info_old` | libkernload | 37 (174/174) | assembly-matched (pic_equal) |
| `_kl_init` | kl_com | 37 (121/121) | assembly-matched (pic_equal) |
| `_processDriver` | owned | 38 (80/90) | intentional-mismatch (different) |
| `_loadDriver` | owned | 44 (170/170) | assembly-matched (pic_equal) |
| `_main` | owned | 52 (238/238) | assembly-matched (pic_equal) |

## ppc

| Function | Group | diff (ref/new insns) | Ledger (pic_equal) |
|---|---|---|---|
| `__dyld_func_lookup` | crt | 0 (4/4) | assembly-matched (pic_equal) |
| `_kern_loader_abort` | libkernload | 0 (68/68) | assembly-matched (pic_equal) |
| `_kern_loader_add_server` | libkernload | 0 (78/78) | assembly-matched (pic_equal) |
| `_kern_loader_delete_server` | libkernload | 0 (78/78) | assembly-matched (pic_equal) |
| `_kern_loader_get_log` | libkernload | 0 (68/68) | assembly-matched (pic_equal) |
| `_kern_loader_load_server` | libkernload | 0 (74/74) | assembly-matched (pic_equal) |
| `_kern_loader_log_level` | libkernload | 0 (68/68) | assembly-matched (pic_equal) |
| `_kern_loader_ping` | libkernload | 0 (33/33) | assembly-matched (pic_equal) |
| `_kern_loader_reply_handler` | libkernload | 0 (66/66) | assembly-matched (pic_equal) |
| `_kern_loader_server_com_port` | libkernload | 0 (91/91) | assembly-matched (pic_equal) |
| `_kern_loader_server_info` | libkernload | 0 (190/190) | assembly-matched (pic_equal) |
| `_kern_loader_server_info_old` | libkernload | 0 (190/190) | assembly-matched (pic_equal) |
| `_kern_loader_server_list` | libkernload | 0 (80/80) | assembly-matched (pic_equal) |
| `_kern_loader_server_task_port` | libkernload | 0 (91/91) | assembly-matched (pic_equal) |
| `_kern_loader_status_port` | libkernload | 0 (29/29) | assembly-matched (pic_equal) |
| `_kern_loader_unload_server` | libkernload | 0 (78/78) | assembly-matched (pic_equal) |
| `_kl_com_error` | kl_com | 0 (17/17) | assembly-matched (pic_equal) |
| `_print_string` | kl_com | 0 (4/4) | assembly-matched (pic_equal) |
| `dyld_stub_binding_helper` | crt | 0 (6/6) | assembly-matched (pic_equal) |
| `start` | crt | 0 (12/12) | assembly-matched (pic_equal) |
| `__dyld_init_check` | crt | 1 (15/15) | assembly-matched (pic_equal) |
| `_kern_loader_look_up` | libkernload | 1 (18/18) | assembly-matched (pic_equal) |
| `_kl_com_get_state` | kl_com | 1 (55/55) | assembly-matched (pic_equal) |
| `_kl_com_load` | kl_com | 1 (34/34) | assembly-matched (pic_equal) |
| `_kl_com_add` | kl_com | 2 (44/44) | assembly-matched (pic_equal) |
| `_kl_com_delete` | kl_com | 2 (31/31) | assembly-matched (pic_equal) |
| `_kl_com_unload` | kl_com | 2 (31/31) | assembly-matched (pic_equal) |
| `_ping` | kl_com | 4 (24/24) | assembly-matched (pic_equal) |
| `__call_mod_init_funcs` | crt | 6 (19/19) | intentional-mismatch (different) |
| `_kl_com_log` | kl_com | 6 (114/114) | assembly-matched (pic_equal) |
| `_kl_com_wait` | kl_com | 6 (31/31) | assembly-matched (pic_equal) |
| `_securityCheck` | owned | 7 (23/23) | assembly-matched (pic_equal) |
| `_kl_init` | kl_com | 11 (110/110) | assembly-matched (pic_equal) |
| `_usage` | owned | 13 (28/28) | assembly-matched (pic_equal) |
| `_inquire` | owned | 14 (39/39) | assembly-matched (pic_equal) |
| `_processDriverList` | owned | 20 (60/60) | assembly-matched (pic_equal) |
| `_processDriver` | owned | 25 (79/79) | assembly-matched (pic_equal) |
| `_getInstanceFile` | owned | 36 (78/78) | assembly-matched (pic_equal) |
| `__start` | crt | 39 (80/80) | intentional-mismatch (different) |
| `_prePostExec` | owned | 48 (106/107) | intentional-mismatch (different) |
| `_securityCheckDir` | owned | 48 (154/154) | assembly-matched (pic_equal) |
| `_configDriver` | owned | 50 (138/138) | assembly-matched (pic_equal) |
| `_unloadDriver` | owned | 66 (143/143) | assembly-matched (pic_equal) |
| `_loadDriver` | owned | 78 (146/146) | assembly-matched (pic_equal) |
| `_main` | owned | 86 (205/205) | assembly-matched (pic_equal) |
## Final state

Date: 2026-09-28. Last kept rebuild: the full universal `rbuild buildpackage`
of driverkit-3 against a private repo with a freshly built kernload.

| Slice | Rebuilt SHA-256 | Size |
|---|---|---|
| i386 | `CFA1627DD7F44AF835D699FD50368B1885DAFDD9F2FCD5A71B508C36BF4B7C25` | 44516 |
| ppc | `F08A579F376CDC99E2F68DEAE3E9E2C51D09E58E6564D13DB9496DDB4B1964EA` | 36352 |

CFLAGS: `-g -O`, then `strip -S` on each slice (Apple's symbol tables
keep locals but no stabs).

- i386 ledger: 78 assembly-matched, 153 intentional-mismatch
- ppc ledger: 83 assembly-matched, 3 intentional-mismatch

Owned functions (23 per slice): i386 20 `pic_equal`, 3 accepted
(`_prePostExec`, `_processDriver`, `_processDriverList`); ppc 22 `pic_equal`,
1 accepted (`_prePostExec`). libkernload: 16/16 `pic_equal` on both slices.
See divergences.md for every accept.
