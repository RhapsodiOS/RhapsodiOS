/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Recovered i386 contracts for the Adaptec 2940 SCSI driver.
 */

#ifndef _ADAPTEC2940TYPES_H
#define _ADAPTEC2940TYPES_H

#include <stddef.h>
#import <driverkit/i386/driverTypes.h>
#import <kernserv/clock_timer.h>
#import <kernserv/queue.h>
#import <bsd/dev/scsireg.h>
#import <driverkit/scsiRequest.h>

/* AIC register offsets. */
#define AIC_SCSISEQ       0x00
#define AIC_SXFRCTL0      0x01
#define AIC_SXFRCTL1      0x02
#define AIC_SCSISIG       0x03
#define AIC_SCSIBUS       0x03
#define AIC_SCSIID        0x05
#define AIC_SSTAT0        0x0b
#define AIC_SSTAT1        0x0c
#define AIC_SSTAT2        0x0d
#define AIC_SBLKCTL       0x1f
#define AIC_SEQCTL        0x60
#define AIC_SEQRAM        0x61
#define AIC_SEQADDR0      0x62
#define AIC_SEQADDR1      0x63
#define AIC_SCBPTR        0x90
#define AIC_INTSTAT       0x91
#define AIC_CLRINT        0x92
#define AIC_ERROR         0x92
#define AIC_DFCNTRL       0x93
#define AIC_DFSTATUS      0x94
#define AIC_DFDAT         0x99
#define AIC_SCBARRAY      0xa0
#define AIC_QINFIFO       0xd5
#define AIC_QOUTFIFO      0xd6
#define AIC_QINCNT        0xd7
#define AIC_QOUTCNT       0xd8

#define TEMODEO           0x80
#define ENSELO            0x40
#define ENSELI            0x20
#define ENRSELI           0x10
#define ENAUTOATNO        0x08
#define ENAUTOATNI        0x04
#define ENAUTOATNP        0x02
#define SCSIRSTO          0x01

#define SEQINT            0x01
#define CMDCMPLT          0x02
#define SCSIINT           0x04
#define BRKADRINT         0x08
#define BAD_PHASE         0x01

#define SELTO             0x80
#define ATNTARG           0x40
#define SCSIRSTI          0x20
#define PHASEMIS          0x10
#define BUSFREE           0x08
#define SCSIPERR          0x04
#define PHASECHG          0x02
#define REQINIT           0x01

#define PERRORDIS         0x80
#define PAUSEDIS          0x40
#define FAILDIS           0x20
#define FASTMODE          0x10
#define BRKADRINTEN       0x08
#define STEP              0x04
#define SEQRESET          0x02
#define LOADRAM           0x01

/* Reference 0xA038 is 1,960 bytes; the sequencer emits byte-wide IO. */
#define A2940_SEQ_IMAGE_SIZE 1960
#define A2940_SEQ_PRESENCE_SIZE 24
#define A2940_HOST_INFO_SIZE 140
#define A2940_CHANNEL_BUS_ID_OFFSET 30
#define A2940_CHANNEL_TARGET_COUNT_OFFSET 31
#define A2940_SCB_SIZE 256
#define A2940_SCB_ALIGNMENT 256
#define A2940_SG_MAX 18
/* IDA's maxTransfer body returns 16 * page_size. */
#define AIC_SG_COUNT 16

typedef struct aic_sg {
	unsigned int address;
	unsigned int length;
} aic_sg_t;

/*
 * The HIM host block is private binary data. Only these byte offsets have
 * been named from the reference's field accesses; keep the full 140-byte
 * allocation intact while the remaining HIM fields are recovered.
 */
typedef struct Adaptec2940HostInfo {
	unsigned char bytes[A2940_HOST_INFO_SIZE];
} Adaptec2940HostInfo;

typedef struct Adaptec2940ChannelInfo {
	void *owner;
	Adaptec2940HostInfo *hostInfo;
} Adaptec2940ChannelInfo;

/* SCB command bytes, host state, scatter/gather list, and queue links. */
typedef struct scb {
	/* Hardware-visible prefix, 0x00..0x1f. */
	struct scb *chain_next;
	Adaptec2940HostInfo *host_info;
	unsigned char scb_status;
	unsigned char host_status;
	unsigned char flags;
	unsigned char manager_status;
	unsigned char target_channel_lun;
	unsigned char control;
	unsigned char command_length;
	unsigned char sg_count;
	unsigned int sg_pointer;
	unsigned int command_pointer;
	unsigned char target_status;
	unsigned char reserved25[3];
	unsigned int residual_data_count;

	/* Reference-private values at 0x20..0x4f. */
	unsigned char reserved32[12];
	unsigned int sense_physical;
	unsigned int reserved48;
	unsigned char cdb[12];
	unsigned int reserved64[3];
	unsigned int host_self;

	/* Up to eighteen 8-byte SG records occupy 0x50..0xdf. */
	aic_sg_t sg_list[A2940_SG_MAX];

	/* Software state at 0xe0..0xff. */
	void *command_buffer;
	ns_time_t start_time;
	port_t timeout_port;
	unsigned int total_transfer_length;
	unsigned char in_use;
	unsigned char reserved245[3];
	queue_chain_t queue_link;
} Adaptec2940SCB;

/* Message queued between the exported bus object and the I/O thread. */
typedef struct Adaptec2940RequestMessage {
	unsigned int channel;
	unsigned int command;
	Adaptec2940HostInfo *host_info;
	void *buffer;
	unsigned int transfer_length;
	int status;
	void *client;
	queue_chain_t queue_link;
} Adaptec2940RequestMessage;

/* The reference timeout message template is six 32-bit words. */
typedef struct Adaptec2940TimeoutMessage {
	unsigned int words[6];
} Adaptec2940TimeoutMessage;

/* Verified host-block offsets used by the first recovered HIM paths. */
#define A2940_HA_IO_BASE_OFFSET       4
#define A2940_HA_IO_BASE_WIDTH        4
#define A2940_HA_BUS_NUMBER_OFFSET    8
#define A2940_HA_DEVICE_NUMBER_OFFSET 9
#define A2940_HA_OPTIONS_OFFSET       13
#define A2940_HA_MODE_OFFSET          16
#define A2940_HA_MODE_WIDTH           2
#define A2940_HA_IRQ_OFFSET           19
#define A2940_HA_SIZE_OFFSET          60
#define A2940_HA_TARGETS_OFFSET       66
#define A2940_HA_SELF_OFFSET           100

/* Kept compatible with the old Project Builder compiler (no C11 assert). */
#define A2940_LAYOUT_ASSERT(name, expression) \
	typedef char name[(expression) ? 1 : -1]

A2940_LAYOUT_ASSERT(a2940_sg_size_is_8, sizeof(aic_sg_t) == 8);
A2940_LAYOUT_ASSERT(a2940_channel_info_size_is_8, sizeof(Adaptec2940ChannelInfo) == 8);
A2940_LAYOUT_ASSERT(a2940_request_message_size_is_36, sizeof(Adaptec2940RequestMessage) == 36);
A2940_LAYOUT_ASSERT(a2940_timeout_message_size_is_24, sizeof(Adaptec2940TimeoutMessage) == 24);
A2940_LAYOUT_ASSERT(a2940_scb_size_is_256, sizeof(Adaptec2940SCB) == A2940_SCB_SIZE);
A2940_LAYOUT_ASSERT(a2940_scb_chain_next_at_0, offsetof(Adaptec2940SCB, chain_next) == 0);
A2940_LAYOUT_ASSERT(a2940_scb_host_info_at_4, offsetof(Adaptec2940SCB, host_info) == 4);
A2940_LAYOUT_ASSERT(a2940_scb_status_at_8, offsetof(Adaptec2940SCB, scb_status) == 8);
A2940_LAYOUT_ASSERT(a2940_scb_host_status_at_9, offsetof(Adaptec2940SCB, host_status) == 9);
A2940_LAYOUT_ASSERT(a2940_scb_flags_at_10, offsetof(Adaptec2940SCB, flags) == 10);
A2940_LAYOUT_ASSERT(a2940_scb_manager_status_at_11, offsetof(Adaptec2940SCB, manager_status) == 11);
A2940_LAYOUT_ASSERT(a2940_scb_tcl_at_12, offsetof(Adaptec2940SCB, target_channel_lun) == 12);
A2940_LAYOUT_ASSERT(a2940_scb_control_at_13, offsetof(Adaptec2940SCB, control) == 13);
A2940_LAYOUT_ASSERT(a2940_scb_command_length_at_14, offsetof(Adaptec2940SCB, command_length) == 14);
A2940_LAYOUT_ASSERT(a2940_scb_sg_count_at_15, offsetof(Adaptec2940SCB, sg_count) == 15);
A2940_LAYOUT_ASSERT(a2940_scb_sg_pointer_at_16, offsetof(Adaptec2940SCB, sg_pointer) == 16);
A2940_LAYOUT_ASSERT(a2940_scb_command_pointer_at_20, offsetof(Adaptec2940SCB, command_pointer) == 20);
A2940_LAYOUT_ASSERT(a2940_scb_target_status_at_24, offsetof(Adaptec2940SCB, target_status) == 24);
A2940_LAYOUT_ASSERT(a2940_scb_residual_at_28, offsetof(Adaptec2940SCB, residual_data_count) == 28);
A2940_LAYOUT_ASSERT(a2940_scb_sense_physical_at_44, offsetof(Adaptec2940SCB, sense_physical) == 44);
A2940_LAYOUT_ASSERT(a2940_scb_cdb_at_52, offsetof(Adaptec2940SCB, cdb) == 52);
A2940_LAYOUT_ASSERT(a2940_scb_host_self_at_76, offsetof(Adaptec2940SCB, host_self) == 76);
A2940_LAYOUT_ASSERT(a2940_scb_sg_count_is_18, sizeof(((Adaptec2940SCB *)0)->sg_list) == 144);
A2940_LAYOUT_ASSERT(a2940_scb_sg_offset_is_80, offsetof(Adaptec2940SCB, sg_list) == 80);
A2940_LAYOUT_ASSERT(a2940_scb_command_buffer_is_224, offsetof(Adaptec2940SCB, command_buffer) == 224);
A2940_LAYOUT_ASSERT(a2940_scb_start_time_is_228, offsetof(Adaptec2940SCB, start_time) == 228);
A2940_LAYOUT_ASSERT(a2940_scb_timeout_port_is_236, offsetof(Adaptec2940SCB, timeout_port) == 236);
A2940_LAYOUT_ASSERT(a2940_scb_total_length_is_240, offsetof(Adaptec2940SCB, total_transfer_length) == 240);
A2940_LAYOUT_ASSERT(a2940_scb_in_use_is_244, offsetof(Adaptec2940SCB, in_use) == 244);
A2940_LAYOUT_ASSERT(a2940_scb_queue_link_is_248, offsetof(Adaptec2940SCB, queue_link) == 248);
A2940_LAYOUT_ASSERT(a2940_scb_queue_previous_is_252, offsetof(Adaptec2940SCB, queue_link) + sizeof(queue_chain_t) / 2 == 252);
A2940_LAYOUT_ASSERT(a2940_request_channel_at_0, offsetof(Adaptec2940RequestMessage, channel) == 0);
A2940_LAYOUT_ASSERT(a2940_request_command_at_4, offsetof(Adaptec2940RequestMessage, command) == 4);
A2940_LAYOUT_ASSERT(a2940_request_host_info_at_8, offsetof(Adaptec2940RequestMessage, host_info) == 8);
A2940_LAYOUT_ASSERT(a2940_request_buffer_at_12, offsetof(Adaptec2940RequestMessage, buffer) == 12);
A2940_LAYOUT_ASSERT(a2940_request_length_at_16, offsetof(Adaptec2940RequestMessage, transfer_length) == 16);
A2940_LAYOUT_ASSERT(a2940_request_status_at_20, offsetof(Adaptec2940RequestMessage, status) == 20);
A2940_LAYOUT_ASSERT(a2940_request_client_at_24, offsetof(Adaptec2940RequestMessage, client) == 24);
A2940_LAYOUT_ASSERT(a2940_request_link_is_28, offsetof(Adaptec2940RequestMessage, queue_link) == 28);
A2940_LAYOUT_ASSERT(a2940_request_message_size_is_36_exact, sizeof(Adaptec2940RequestMessage) == 36);
A2940_LAYOUT_ASSERT(a2940_host_info_is_140, sizeof(Adaptec2940HostInfo) == A2940_HOST_INFO_SIZE);
A2940_LAYOUT_ASSERT(a2940_channel_info_owner_at_0, offsetof(Adaptec2940ChannelInfo, owner) == 0);
A2940_LAYOUT_ASSERT(a2940_channel_info_host_at_4, offsetof(Adaptec2940ChannelInfo, hostInfo) == 4);
A2940_LAYOUT_ASSERT(a2940_sense_data_size_is_26, sizeof(esense_reply_t) == 26);
A2940_LAYOUT_ASSERT(a2940_scsi_request_size_is_84, sizeof(IOSCSIRequest) == 84);
A2940_LAYOUT_ASSERT(a2940_scsi_request_sense_at_56, offsetof(IOSCSIRequest, senseData) == 56);

#endif /* _ADAPTEC2940TYPES_H */
