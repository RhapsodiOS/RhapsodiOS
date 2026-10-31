import re
import unittest
import ctypes
from pathlib import Path


ROOT = Path(__file__).resolve().parents[6]
DRIVER = ROOT / "src/drivers-i386/scsi/drvBusLogic/BusLogic.drvproj/BusLogic.lksproj"
TYPES = (DRIVER / "BusLogicTypes.h").read_text()
INLINE = (DRIVER / "BusLogicInline.h").read_text()
CONTROLLER = (DRIVER / "BusLogicController.h").read_text()
CONTROLLER_IMPL = (DRIVER / "BusLogicController.m").read_text()
THREAD = (DRIVER / "BusLogicThread.m").read_text()
ROUTINES = (DRIVER / "BusLogicRoutines.m").read_text()


def definition(pattern):
    match = re.search(pattern, TYPES, re.S)
    if not match:
        raise AssertionError(f"missing type matching {pattern!r}")
    return match.group(1)


class ExtendedBusLogicAbiTests(unittest.TestCase):
    def test_extended_mailbox_init_command_is_defined(self):
        self.assertRegex(TYPES, r"#define\s+BL_CMD_INIT_EXT_MBOX\s+0x81\b")

    def test_mailbox_is_eight_bytes_with_status_at_byte_seven(self):
        body = definition(r"typedef\s+struct\s*\{(.*?)\}\s*bl_mb_t\s*;")
        self.assertIn("ccb_addr[4]", body)
        self.assertIn("reserved[3]", body)
        self.assertIn("mb_stat", body)
        address = body.index("ccb_addr[4]")
        padding = body.index("reserved[3]")
        status = body.index("mb_stat")
        self.assertLess(address, padding)
        self.assertLess(padding, status)

    def test_mailbox_area_has_two_sixteen_entry_rings_and_six_cursors(self):
        body = definition(r"struct\s+bl_mb_area\s*\{(.*?)\};")
        self.assertRegex(body, r"bl_mb_t\s+mb_out\[BL_MB_CNT\]")
        self.assertRegex(body, r"bl_mb_t\s+mb_in\[BL_MB_CNT\]")
        self.assertEqual(len(re.findall(r"bl_mb_t\s*\*", body)), 6)

    def test_scatter_gather_entry_holds_two_32_bit_values(self):
        body = definition(r"struct\s+bl_sg\s*\{(.*?)\};")
        self.assertRegex(body, r"len\[4\]")
        self.assertRegex(body, r"addr\[4\]")

    def test_extended_ccb_keeps_reference_offsets_and_284_byte_stride(self):
        body = definition(r"struct\s+ccb\s*\{(.*?)\};")
        self.assertIn("data_len[4]", body)
        self.assertIn("data_addr[4]", body)
        self.assertLess(body.index("reserved_link[2]"), body.index("host_status"))
        self.assertLess(body.index("host_status"), body.index("target_status"))
        self.assertLess(body.index("cdb;"), body.index("wire_padding[6]"))
        self.assertRegex(body, r"bl_sg\s+sg_list\[BL_SG_COUNT\]")
        self.assertRegex(body, r"unsigned\s+int\s+physical_addr\s*;")
        self.assertRegex(body, r"struct\s+ccb\s*\*\s*free_next\s*;")

    def test_32_bit_little_endian_helpers_are_available(self):
        self.assertIn("bl_put_32", INLINE)
        self.assertIn("bl_get_32", INLINE)

    def test_controller_owns_the_reference_free_list_and_level_irq_state(self):
        self.assertIn("*blCcbFreeList", CONTROLLER)
        self.assertIn("levelIRQ", CONTROLLER)
        self.assertLess(CONTROLLER.index("blCcbFreeList"), CONTROLLER.index("commandQ"))
        self.assertGreater(CONTROLLER.index("ioThreadRunning"), CONTROLLER.index("interruptPortKern"))

    def test_completion_handles_host_adapter_parity_error(self):
        self.assertRegex(TYPES, r"#define\s+BL_HOST_ADAPTER_PARITY_ERROR\s+0x34\b")
        self.assertIn("BL_HOST_ADAPTER_PARITY_ERROR", THREAD)
        self.assertIn("SR_IOST_PARITY", THREAD)

    def test_mailbox_setup_uses_extended_mailbox_command_and_builds_free_list(self):
        self.assertIn("BL_CMD_INIT_EXT_MBOX", ROUTINES)
        self.assertIn("*freeList", ROUTINES)
        self.assertIn("ccb->physical_addr", ROUTINES)
        self.assertIn("blCcbFreeList", CONTROLLER)

    def test_dma_and_irq_resources_follow_reference_bus_policy(self):
        init = CONTROLLER_IMPL[CONTROLLER_IMPL.index("- initFromDeviceDescription:deviceDescription"):CONTROLLER_IMPL.index("- (unsigned)maxTransfer")]
        self.assertIn("if (config.dma_channel != 0xff)", init)
        self.assertIn("[deviceDescription numChannels] < 1", init)
        self.assertIn("busType != BL_BUS_PCI", init)
        self.assertIn("[deviceDescription numInterrupts] < 1", init)
        self.assertIn("setTransferMode:IO_Cascade", init)
        self.assertIn("forChannel:0", init)
        self.assertIn("enableChannel:0", init)

    def test_mailbox_setup_failure_cannot_leave_a_partial_ccb_free_list(self):
        self.assertIn("#import <string.h>", ROUTINES)
        self.assertIn("*freeList = NULL", ROUTINES)

    def test_extended_i386_structure_sizes_and_offsets(self):
        class Mailbox(ctypes.Structure):
            _pack_ = 4
            _fields_ = [("ccb_addr", ctypes.c_uint32), ("reserved", ctypes.c_uint8 * 3), ("status", ctypes.c_uint8)]

        class MailboxArea(ctypes.Structure):
            _pack_ = 4
            _fields_ = [
                ("out", Mailbox * 16), ("inbound", Mailbox * 16),
                ("cursors", ctypes.c_uint32 * 6),
            ]

        class CCB(ctypes.Structure):
            _pack_ = 4
            _fields_ = [
                ("op", ctypes.c_uint8), ("flags", ctypes.c_uint8),
                ("cdb_len", ctypes.c_uint8), ("sense_len", ctypes.c_uint8),
                ("data_len", ctypes.c_uint32), ("data_addr", ctypes.c_uint32),
                ("reserved_link", ctypes.c_uint8 * 2),
                ("host_status", ctypes.c_uint8), ("target_status", ctypes.c_uint8),
                ("reserved", ctypes.c_uint8 * 2), ("cdb", ctypes.c_uint8 * 16),
                ("wire_padding", ctypes.c_uint8 * 6),
                ("sg_list", ctypes.c_uint32 * (17 * 2)),
                ("dma_list", ctypes.c_uint32 * 17), ("total_xfer_len", ctypes.c_uint32),
                ("start_time", ctypes.c_uint64), ("timeout_port", ctypes.c_uint32),
                ("cmd_buf", ctypes.c_uint32), ("in_use", ctypes.c_uint32),
                ("ccb_links", ctypes.c_uint32 * 2), ("physical_addr", ctypes.c_uint32),
                ("free_next", ctypes.c_uint32),
            ]

        self.assertEqual(ctypes.sizeof(Mailbox), 8)
        self.assertEqual(Mailbox.status.offset, 7)
        self.assertEqual(ctypes.sizeof(MailboxArea), 280)
        self.assertEqual(CCB.sg_list.offset, 40)
        self.assertEqual(CCB.dma_list.offset, 176)
        self.assertEqual(CCB.total_xfer_len.offset, 244)
        self.assertEqual(CCB.start_time.offset, 248)
        self.assertEqual(CCB.cmd_buf.offset, 260)
        self.assertEqual(CCB.in_use.offset, 264)
        self.assertEqual(CCB.physical_addr.offset, 276)
        self.assertEqual(ctypes.sizeof(CCB), 284)


if __name__ == "__main__":
    unittest.main()
