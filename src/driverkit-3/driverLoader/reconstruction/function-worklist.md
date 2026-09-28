# driverLoader function worklist

Date: 2026-09-27

Rebuilt i386: `181426E4F11DF9CD6E0FBB02F986555455E31A5C894E0F9A7FBB9DFA862A004E`
Rebuilt ppc: `E97B66CD5132F0DC8554B8B40C28AA8FB47868AC1D73B3E6AB7DF23E331A3A54`

Rows come from `binrecon function --list`, cheapest difference first. libDriver
functions are not listed: they are the i386 accept in divergences.md.

## i386

| Function | Group | diff (ref/new insns) | Status |
|---|---|---|---|
| `__dyld_func_lookup` | crt | 0 (1/1) | open |
| `_print_string` | kl_com | 0 (6/6) | identical |
| `dyld_stub_binding_helper` | crt | 0 (2/2) | open |
| `start` | crt | 0 (12/12) | identical |
| `__call_mod_init_funcs` | crt | 1 (15/15) | open |
| `_kern_loader_status_port` | libkernload | 1 (24/24) | open |
| `__dyld_init_check` | crt | 2 (14/14) | open |
| `_kern_loader_look_up` | libkernload | 2 (15/15) | open |
| `_kern_loader_ping` | libkernload | 2 (29/29) | open |
| `_kl_com_error` | kl_com | 2 (14/14) | open |
| `_securityCheck` | owned | 3 (24/24) | open |
| `_ping` | kl_com | 4 (25/25) | open |
| `_kl_com_wait` | kl_com | 6 (32/32) | open |
| `_usage` | owned | 6 (28/28) | open |
| `_inquire` | owned | 8 (32/32) | open |
| `_kern_loader_reply_handler` | libkernload | 8 (67/67) | open |
| `_kl_com_get_state` | kl_com | 8 (56/56) | open |
| `_kern_loader_abort` | libkernload | 14 (69/69) | open |
| `_kern_loader_get_log` | libkernload | 14 (69/69) | open |
| `_kern_loader_load_server` | libkernload | 14 (74/74) | open |
| `_kern_loader_log_level` | libkernload | 14 (69/69) | open |
| `_kern_loader_add_server` | libkernload | 15 (79/79) | open |
| `_kern_loader_delete_server` | libkernload | 15 (79/79) | open |
| `_kern_loader_unload_server` | libkernload | 15 (79/79) | open |
| `_kern_loader_server_list` | libkernload | 16 (76/76) | open |
| `_kl_com_delete` | kl_com | 16 (37/34) | open |
| `_kl_com_unload` | kl_com | 16 (37/34) | open |
| `__start` | crt | 17 (67/67) | open |
| `_kl_com_load` | kl_com | 17 (41/40) | open |
| `_kern_loader_server_com_port` | libkernload | 20 (91/91) | open |
| `_kern_loader_server_task_port` | libkernload | 20 (91/91) | open |
| `_kl_com_add` | kl_com | 23 (51/48) | open |
| `_kern_loader_server_info` | libkernload | 37 (174/174) | open |
| `_kern_loader_server_info_old` | libkernload | 37 (174/174) | open |
| `_processDriverList` | owned | 40 (62/64) | open |
| `_getInstanceFile` | owned | 44 (86/89) | open |
| `_configDriver` | owned | 45 (176/169) | open |
| `_prePostExec` | owned | 49 (128/128) | open |
| `_processDriver` | owned | 52 (80/70) | open |
| `_unloadDriver` | owned | 59 (172/169) | open |
| `_kl_init` | kl_com | 68 (121/122) | open |
| `_kl_com_log` | kl_com | 70 (129/123) | open |
| `_securityCheckDir` | owned | 85 (191/192) | open |
| `_loadDriver` | owned | 97 (170/176) | open |
| `_main` | owned | 132 (238/241) | open |

## ppc

| Function | Group | diff (ref/new insns) | Status |
|---|---|---|---|
| `__dyld_func_lookup` | crt | 0 (4/4) | identical |
| `_print_string` | kl_com | 0 (4/4) | identical |
| `dyld_stub_binding_helper` | crt | 0 (6/6) | identical |
| `start` | crt | 0 (12/12) | identical |
| `__dyld_init_check` | crt | 1 (15/15) | identical |
| `_kl_com_error` | kl_com | 3 (17/17) | open |
| `__call_mod_init_funcs` | crt | 6 (19/19) | open |
| `_kern_loader_status_port` | libkernload | 6 (29/29) | open |
| `_securityCheck` | owned | 7 (23/23) | open |
| `_kern_loader_ping` | libkernload | 8 (33/33) | open |
| `_kern_loader_look_up` | libkernload | 9 (18/18) | open |
| `_kern_loader_reply_handler` | libkernload | 9 (66/66) | open |
| `_ping` | kl_com | 9 (24/24) | open |
| `_kl_com_wait` | kl_com | 15 (31/31) | open |
| `_usage` | owned | 15 (28/27) | open |
| `_kl_com_delete` | kl_com | 18 (31/30) | open |
| `_kl_com_load` | kl_com | 18 (34/33) | open |
| `_kl_com_unload` | kl_com | 18 (31/30) | open |
| `_kl_com_add` | kl_com | 21 (44/43) | open |
| `_inquire` | owned | 22 (39/39) | open |
| `_kl_com_get_state` | kl_com | 26 (55/55) | open |
| `_processDriverList` | owned | 36 (60/59) | open |
| `_kern_loader_server_list` | libkernload | 37 (80/87) | open |
| `__start` | crt | 39 (80/80) | open |
| `_kern_loader_load_server` | libkernload | 42 (74/89) | open |
| `_kern_loader_add_server` | libkernload | 44 (78/93) | open |
| `_kern_loader_delete_server` | libkernload | 44 (78/93) | open |
| `_kern_loader_unload_server` | libkernload | 44 (78/93) | open |
| `_kern_loader_abort` | libkernload | 46 (68/83) | open |
| `_kern_loader_get_log` | libkernload | 46 (68/83) | open |
| `_kern_loader_log_level` | libkernload | 46 (68/83) | open |
| `_kern_loader_server_com_port` | libkernload | 46 (91/98) | open |
| `_kern_loader_server_task_port` | libkernload | 46 (91/98) | open |
| `_getInstanceFile` | owned | 48 (78/78) | open |
| `_processDriver` | owned | 63 (79/60) | open |
| `_configDriver` | owned | 69 (138/129) | open |
| `_kl_init` | kl_com | 71 (110/110) | open |
| `_kl_com_log` | kl_com | 74 (114/111) | open |
| `_prePostExec` | owned | 88 (106/107) | open |
| `_kern_loader_server_info` | libkernload | 97 (190/197) | open |
| `_kern_loader_server_info_old` | libkernload | 97 (190/197) | open |
| `_unloadDriver` | owned | 102 (143/143) | open |
| `_securityCheckDir` | owned | 111 (154/148) | open |
| `_loadDriver` | owned | 153 (146/146) | open |
| `_main` | owned | 165 (205/204) | open |
