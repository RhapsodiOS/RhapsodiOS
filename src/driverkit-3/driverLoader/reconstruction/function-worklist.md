# driverLoader function worklist

Date: 2026-09-28

Rebuilt i386: `0A61F1C3997DFFD8906EC6ED110B85147B748C1C3835D335E0657797BCE3E11A`
Rebuilt ppc: `5C35BCBCC070BD3302E91EAA7841B0F3B67052A5916A432D98194336AA3CC1D1`

Rows come from `binrecon function --list`, cheapest difference first. libDriver
functions are not listed: they are the i386 accept in divergences.md.
CFLAGS settled at `-g -O` with `strip -S` per slice (Task 5).

## i386

| Function | Group | diff (ref/new insns) | Ledger (pic_equal) |
|---|---|---|---|
| `__dyld_func_lookup` | crt | 0 (1/1) | unexamined (-) |
| `_print_string` | kl_com | 0 (6/6) | assembly-matched (pic_equal) |
| `dyld_stub_binding_helper` | crt | 0 (2/2) | unexamined (-) |
| `start` | crt | 0 (12/12) | unexamined (-) |
| `__call_mod_init_funcs` | crt | 1 (15/15) | unexamined (-) |
| `_kern_loader_status_port` | libkernload | 1 (24/24) | unexamined (pic_equal) |
| `__dyld_init_check` | crt | 2 (14/14) | unexamined (-) |
| `_kern_loader_look_up` | libkernload | 2 (15/15) | unexamined (pic_equal) |
| `_kern_loader_ping` | libkernload | 2 (29/29) | unexamined (pic_equal) |
| `_kl_com_error` | kl_com | 2 (14/14) | assembly-matched (pic_equal) |
| `_securityCheck` | owned | 3 (24/24) | assembly-matched (pic_equal) |
| `_ping` | kl_com | 4 (25/25) | assembly-matched (pic_equal) |
| `_kl_com_delete` | kl_com | 5 (37/37) | assembly-matched (pic_equal) |
| `_kl_com_unload` | kl_com | 5 (37/37) | assembly-matched (pic_equal) |
| `_kl_com_load` | kl_com | 6 (41/41) | assembly-matched (pic_equal) |
| `_kl_com_wait` | kl_com | 6 (32/32) | assembly-matched (pic_equal) |
| `_usage` | owned | 6 (28/28) | assembly-matched (pic_equal) |
| `_inquire` | owned | 8 (32/32) | assembly-matched (pic_equal) |
| `_kern_loader_reply_handler` | libkernload | 8 (67/67) | unexamined (pic_equal) |
| `_kl_com_get_state` | kl_com | 8 (56/56) | assembly-matched (pic_equal) |
| `_kl_com_add` | kl_com | 10 (51/51) | assembly-matched (pic_equal) |
| `_kern_loader_abort` | libkernload | 14 (69/69) | unexamined (pic_equal) |
| `_kern_loader_get_log` | libkernload | 14 (69/69) | unexamined (pic_equal) |
| `_kern_loader_load_server` | libkernload | 14 (74/74) | unexamined (pic_equal) |
| `_kern_loader_log_level` | libkernload | 14 (69/69) | unexamined (pic_equal) |
| `_kern_loader_add_server` | libkernload | 15 (79/79) | unexamined (pic_equal) |
| `_kern_loader_delete_server` | libkernload | 15 (79/79) | unexamined (pic_equal) |
| `_kern_loader_unload_server` | libkernload | 15 (79/79) | unexamined (pic_equal) |
| `_kern_loader_server_list` | libkernload | 16 (76/76) | unexamined (pic_equal) |
| `__start` | crt | 17 (67/67) | unexamined (-) |
| `_kern_loader_server_com_port` | libkernload | 20 (91/91) | unexamined (pic_equal) |
| `_kern_loader_server_task_port` | libkernload | 20 (91/91) | unexamined (pic_equal) |
| `_getInstanceFile` | owned | 21 (86/86) | assembly-matched (pic_equal) |
| `_processDriverList` | owned | 22 (62/65) | intentional-mismatch (different) |
| `_securityCheckDir` | owned | 32 (191/191) | assembly-matched (pic_equal) |
| `_prePostExec` | owned | 33 (128/128) | intentional-mismatch (different) |
| `_configDriver` | owned | 34 (176/176) | assembly-matched (pic_equal) |
| `_kl_com_log` | kl_com | 35 (129/129) | assembly-matched (pic_equal) |
| `_unloadDriver` | owned | 36 (172/172) | assembly-matched (pic_equal) |
| `_kern_loader_server_info` | libkernload | 37 (174/174) | unexamined (pic_equal) |
| `_kern_loader_server_info_old` | libkernload | 37 (174/174) | unexamined (pic_equal) |
| `_kl_init` | kl_com | 37 (121/121) | assembly-matched (pic_equal) |
| `_processDriver` | owned | 38 (80/90) | intentional-mismatch (different) |
| `_loadDriver` | owned | 44 (170/170) | assembly-matched (pic_equal) |
| `_main` | owned | 52 (238/238) | assembly-matched (pic_equal) |

## ppc

| Function | Group | diff (ref/new insns) | Ledger (pic_equal) |
|---|---|---|---|
| `__dyld_func_lookup` | crt | 0 (4/4) | unexamined (-) |
| `_print_string` | kl_com | 0 (4/4) | assembly-matched (pic_equal) |
| `dyld_stub_binding_helper` | crt | 0 (6/6) | unexamined (-) |
| `start` | crt | 0 (12/12) | unexamined (-) |
| `__dyld_init_check` | crt | 1 (15/15) | unexamined (-) |
| `_kl_com_error` | kl_com | 3 (17/17) | assembly-matched (pic_equal) |
| `__call_mod_init_funcs` | crt | 6 (19/19) | unexamined (-) |
| `_kern_loader_status_port` | libkernload | 6 (29/29) | unexamined (different) |
| `_securityCheck` | owned | 7 (23/23) | assembly-matched (pic_equal) |
| `_kern_loader_ping` | libkernload | 8 (33/33) | unexamined (different) |
| `_kern_loader_look_up` | libkernload | 9 (18/18) | unexamined (different) |
| `_kern_loader_reply_handler` | libkernload | 9 (66/66) | unexamined (different) |
| `_ping` | kl_com | 9 (24/24) | assembly-matched (pic_equal) |
| `_kl_com_load` | kl_com | 10 (34/34) | assembly-matched (pic_equal) |
| `_kl_com_delete` | kl_com | 11 (31/31) | assembly-matched (pic_equal) |
| `_kl_com_unload` | kl_com | 11 (31/31) | assembly-matched (pic_equal) |
| `_kl_com_get_state` | kl_com | 13 (55/55) | assembly-matched (pic_equal) |
| `_usage` | owned | 13 (28/28) | assembly-matched (pic_equal) |
| `_inquire` | owned | 14 (39/39) | assembly-matched (pic_equal) |
| `_kl_com_wait` | kl_com | 15 (31/31) | assembly-matched (pic_equal) |
| `_kl_com_add` | kl_com | 16 (44/44) | assembly-matched (pic_equal) |
| `_processDriverList` | owned | 20 (60/60) | assembly-matched (pic_equal) |
| `_processDriver` | owned | 25 (79/79) | assembly-matched (pic_equal) |
| `_getInstanceFile` | owned | 36 (78/78) | assembly-matched (pic_equal) |
| `_kern_loader_server_list` | libkernload | 37 (80/87) | unexamined (different) |
| `__start` | crt | 39 (80/80) | unexamined (-) |
| `_kern_loader_load_server` | libkernload | 42 (74/89) | unexamined (different) |
| `_kern_loader_add_server` | libkernload | 44 (78/93) | unexamined (different) |
| `_kern_loader_delete_server` | libkernload | 44 (78/93) | unexamined (different) |
| `_kern_loader_unload_server` | libkernload | 44 (78/93) | unexamined (different) |
| `_kern_loader_abort` | libkernload | 46 (68/83) | unexamined (different) |
| `_kern_loader_get_log` | libkernload | 46 (68/83) | unexamined (different) |
| `_kern_loader_log_level` | libkernload | 46 (68/83) | unexamined (different) |
| `_kern_loader_server_com_port` | libkernload | 46 (91/98) | unexamined (different) |
| `_kern_loader_server_task_port` | libkernload | 46 (91/98) | unexamined (different) |
| `_securityCheckDir` | owned | 48 (154/154) | assembly-matched (pic_equal) |
| `_configDriver` | owned | 50 (138/138) | assembly-matched (pic_equal) |
| `_prePostExec` | owned | 51 (106/107) | intentional-mismatch (different) |
| `_kl_com_log` | kl_com | 58 (114/114) | assembly-matched (pic_equal) |
| `_unloadDriver` | owned | 66 (143/143) | assembly-matched (pic_equal) |
| `_kl_init` | kl_com | 69 (110/110) | assembly-matched (pic_equal) |
| `_loadDriver` | owned | 78 (146/146) | assembly-matched (pic_equal) |
| `_main` | owned | 86 (205/205) | assembly-matched (pic_equal) |
| `_kern_loader_server_info` | libkernload | 97 (190/197) | unexamined (different) |
| `_kern_loader_server_info_old` | libkernload | 97 (190/197) | unexamined (different) |
