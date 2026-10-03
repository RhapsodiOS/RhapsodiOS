#include <stddef.h>
#include "../../BusLogicFP.drvproj/BusLogicFP.lksproj/BusLogicFPPrivate.h"

#define ABI_ASSERT(name, condition) typedef char abi_assert_##name[(condition) ? 1 : -1]
ABI_ASSERT(sccb_size, sizeof(struct sccb) == 260);
ABI_ASSERT(sccb_callback, offsetof(struct sccb, SccbCallback) == 40);
ABI_ASSERT(sccb_io_port, offsetof(struct sccb, SccbIOPort) == 44);
ABI_ASSERT(sccb_sg_start, offsetof(struct sccb, SGEntries) == 100);
ABI_ASSERT(sccb_command, offsetof(struct sccb, CommandRecord) == 236);
ABI_ASSERT(sccb_controller, offsetof(struct sccb, Controller) == 248);
ABI_ASSERT(sccb_timeout_scheduled, offsetof(struct sccb, TimeoutScheduled) == 244);
ABI_ASSERT(sccb_links, offsetof(struct sccb, QueueLinks) == 252);
ABI_ASSERT(sccb_next, offsetof(struct sccb, QueueLinks.next) == 252);
ABI_ASSERT(sccb_prev, offsetof(struct sccb, QueueLinks.prev) == 256);
ABI_ASSERT(sg_entry_size, sizeof(struct sccb_sg_entry) == 8);
ABI_ASSERT(sg_capacity, sizeof(((struct sccb *)0)->SGEntries) / 8 == 17);
ABI_ASSERT(manager_size, sizeof(struct sccb_mgr_info) == 64);
ABI_ASSERT(manager_owner, offsetof(struct sccb_mgr_info, owner) == 28);
ABI_ASSERT(card_size, sizeof(struct sccb_card) == 20);
ABI_ASSERT(card_index, offsetof(struct sccb_card, discQCount) == 14);
ABI_ASSERT(card_flags, offsetof(struct sccb_card, globalFlags) == 16);
ABI_ASSERT(card_host_id, offsetof(struct sccb_card, ourId) == 17);
ABI_ASSERT(card_io_port, offsetof(struct sccb_card, ioPort) == 8);
ABI_ASSERT(card_command_count, offsetof(struct sccb_card, cmdCounter) == 12);
ABI_ASSERT(card_queue_cursor, offsetof(struct sccb_card, tagQ_Lst) == 15);
ABI_ASSERT(target_size, sizeof(struct sccb_mgr_target) == 212);
ABI_ASSERT(target_slots, offsetof(struct sccb_mgr_target, disconnected) == 64);
ABI_ASSERT(target_select_head, offsetof(struct sccb_mgr_target, selectHead) == 196);
ABI_ASSERT(target_select_tail, offsetof(struct sccb_mgr_target, selectTail) == 200);
ABI_ASSERT(target_eligible, offsetof(struct sccb_mgr_target, selectEligible) == 204);
ABI_ASSERT(target_count, offsetof(struct sccb_mgr_target, selectCount) == 205);
ABI_ASSERT(target_sync_value, offsetof(struct sccb_mgr_target, syncValue) == 208);
ABI_ASSERT(command_size, sizeof(struct blfp_command_record) == 48);
ABI_ASSERT(command_result, offsetof(struct blfp_command_record, result) == 16);
ABI_ASSERT(command_timestamp, offsetof(struct blfp_command_record, timestamp) == 32);
ABI_ASSERT(command_links, offsetof(struct blfp_command_record, queue) == 40);
ABI_ASSERT(controller_size, sizeof(struct blfp_controller_abi) == 0x294);
ABI_ASSERT(controller_io_base, offsetof(struct blfp_controller_abi, ioBase) == 0x244);
ABI_ASSERT(controller_irq, offsetof(struct blfp_controller_abi, irq) == 0x248);
ABI_ASSERT(controller_mgr, offsetof(struct blfp_controller_abi, sccbMgr) == 0x24c);
ABI_ASSERT(controller_card, offsetof(struct blfp_controller_abi, cardHandle) == 0x254);
ABI_ASSERT(controller_free_queue, offsetof(struct blfp_controller_abi, sccbFreeList) == 0x258);
ABI_ASSERT(controller_command_queue, offsetof(struct blfp_controller_abi, commandQ) == 0x260);
ABI_ASSERT(controller_lock, offsetof(struct blfp_controller_abi, commandLock) == 0x268);
ABI_ASSERT(controller_outstanding, offsetof(struct blfp_controller_abi, outstandingQ) == 0x26c);
ABI_ASSERT(controller_stats, offsetof(struct blfp_controller_abi, totalCommands) == 0x280);
ABI_ASSERT(controller_interrupt_port, offsetof(struct blfp_controller_abi, interruptPortKern) == 0x284);
ABI_ASSERT(controller_bus_type, offsetof(struct blfp_controller_abi, busType) == 0x28c);
ABI_ASSERT(controller_target_count, offsetof(struct blfp_controller_abi, targetsPerBus) == 0x291);
int reconstruction_layout_test(void) { return 0; }

