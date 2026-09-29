#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Interceptor_types.h"
#include "Private/InterceptorIPC.h"
#include "test_support.h"

enum { TestAddRect, TestRemoveRect, TestSetNotifyPort,
       TestScreenCount, TestHideCursor, TestShowCursor,
       TestRepairPalette, TestDamagedPalette,
       TestMapFrameBuffer, TestUnmapFrameBuffer, TestFrameBufferInfo,
       TestAccessTokens,
       TestBM34ToBM35, TestBM35ToBM34, TestBM256ToBM38, TestBM38ToBM256,
       TestCompositeBits };
enum { TestSuccessReply, TestErrorReply, TestWrongReplyID, TestShortReply, TestSendFailure };

static int expectedOperation;
static int expectedReply;
static int expectedSendResult;
static port_t expectedContextPort;
static port_t expectedReplyPort;
static port_t expectedNotifyPort;
static port_t expectedExceptionPort;
static unsigned int expectedUniqueID;
static InterceptedRectangle expectedRectangle;
static InterceptedRectangle replyRectangle;
static int expectedOperationResult;
static int expectedScreenNumber;
static port_t expectedTaskPort;
static unsigned int expectedAddress;
static port_t expectedMasterPort;
static int expectedIOObjectNumber;
static port_t expectedDevicePort;
static char expectedDriver[80];
static char expectedPixelEncoding[64];
static int expectedFrameBufferFields[8];
static unsigned short expectedTableWords[4] = { 1, 2, 3, 4 };
static unsigned char expectedCompositeBits[64];
static int expectedCompositeFields[10];

#if defined(__ppc__) || defined(__POWERPC__)
#define EXPECTED_BM256_TO_BM38_TYPE 0x02201000
#define EXPECTED_BM38_TO_BM256_TYPE 0x08084000
#elif defined(__i386__)
#define EXPECTED_BM256_TO_BM38_TYPE 0x01002002
#define EXPECTED_BM38_TO_BM256_TYPE 0x04000808
#endif

#if defined(__ppc__) || defined(__POWERPC__)
#define EXPECTED_INTEGER_TYPE 0x02200018
#define EXPECTED_RECT_TYPE    0x02200088
#define EXPECTED_PORT_TYPE    0x06200018
#elif defined(__i386__)
#define EXPECTED_INTEGER_TYPE 0x10012002
#define EXPECTED_RECT_TYPE    0x10082002
#define EXPECTED_PORT_TYPE    0x10012006
#else
#error "IPC transport checks require 32-bit PowerPC or i386"
#endif

static void TestSetLongType(int *words, int size)
{
    msg_type_long_t descriptor;
    memset(&descriptor, 0, sizeof(descriptor));
    descriptor.msg_type_header.msg_type_inline = 1;
    descriptor.msg_type_header.msg_type_longform = 1;
    descriptor.msg_type_long_name = 12;
    descriptor.msg_type_long_size = size;
    descriptor.msg_type_long_number = 1;
    memcpy(words, &descriptor, sizeof(descriptor));
}

static void TestSetOutOfLineLongType(int *words, int count)
{
    msg_type_long_t descriptor;
    memset(&descriptor, 0, sizeof(descriptor));
    descriptor.msg_type_header.msg_type_inline = 0;
    descriptor.msg_type_header.msg_type_longform = 1;
    descriptor.msg_type_long_name = 1;
    descriptor.msg_type_long_size = 16;
    descriptor.msg_type_long_number = count;
    memcpy(words, &descriptor, sizeof(descriptor));
}

int InterceptorTestMsgRPC(msg_header_t *header, int option, int sendSize,
                          int receiveSize, int timeout)
{
    int *words = (int *)((char *)header + sizeof(*header));
    int replyID;
    int successSize;

    TestCheck(option == 0 && receiveSize == 0 && timeout == 0,
              "RPC uses the reference option and timeout arguments");
    TestCheck(header->msg_type == 0x100 &&
              header->msg_remote_port == expectedContextPort &&
              header->msg_local_port == expectedReplyPort,
              "RPC header carries context and reply ports in reference order");

    if (expectedOperation == TestAddRect) {
        TestCheck(sendSize == 76 && header->msg_size == 60 &&
                  header->msg_simple == 1 && header->msg_id == 0x1C23,
                  "AddRect request ID and send/header sizes");
        TestCheck(words[0] == EXPECTED_RECT_TYPE &&
                  memcmp(&words[1], &expectedRectangle, sizeof(expectedRectangle)) == 0,
                  "AddRect request descriptor and eight integer fields");
        replyID = 0x1C87;
        successSize = 76;
    } else if (expectedOperation == TestRemoveRect) {
        TestCheck(sendSize == 40 && header->msg_size == 32 &&
                  header->msg_simple == 1 && header->msg_id == 0x1C24,
                  "RemoveRect request ID and send/header sizes");
        TestCheck(words[0] == EXPECTED_INTEGER_TYPE &&
                  (unsigned int)words[1] == expectedUniqueID,
                  "RemoveRect integer descriptor and unique ID");
        replyID = 0x1C88;
        successSize = 40;
    } else if (expectedOperation == TestSetNotifyPort) {
        TestCheck(sendSize == 40 && header->msg_size == 40 &&
                  header->msg_simple == 0 && header->msg_id == 0x1C25,
                  "SetNotifyPort request ID and send/header sizes");
        TestCheck(words[0] == EXPECTED_PORT_TYPE &&
                  (port_t)words[1] == expectedNotifyPort &&
                  words[2] == EXPECTED_PORT_TYPE &&
                  (port_t)words[3] == expectedExceptionPort,
                  "SetNotifyPort port descriptors and payload");
        replyID = 0x1C89;
        successSize = 40;
    } else if (expectedOperation == TestMapFrameBuffer) {
        TestCheck(sendSize == 48 && header->msg_size == 40 &&
                  header->msg_simple == 0 && header->msg_id == 7198,
                  "MapFrameBuffer request ID and header sizes");
        TestCheck(words[0] == EXPECTED_INTEGER_TYPE &&
                  words[1] == expectedScreenNumber &&
                  words[2] == EXPECTED_PORT_TYPE &&
                  (port_t)words[3] == expectedTaskPort,
                  "MapFrameBuffer sends screen and task port descriptors");
        replyID = 7298;
        successSize = 48;
    } else if (expectedOperation == TestUnmapFrameBuffer) {
        TestCheck(sendSize == 40 && header->msg_size == 48 &&
                  header->msg_simple == 0 && header->msg_id == 7219,
                  "UnmapFrameBuffer request ID and header sizes");
        TestCheck(words[0] == EXPECTED_INTEGER_TYPE &&
                  words[1] == expectedScreenNumber &&
                  words[2] == EXPECTED_PORT_TYPE &&
                  (port_t)words[3] == expectedTaskPort &&
                  words[4] == EXPECTED_INTEGER_TYPE &&
                  (unsigned int)words[5] == expectedAddress,
                  "UnmapFrameBuffer sends screen, task port, and address");
        replyID = 7319;
        successSize = 40;
    } else if (expectedOperation == TestFrameBufferInfo) {
        TestCheck(sendSize == 272 && header->msg_size == 32 &&
                  header->msg_simple == 1 && header->msg_id == 7201,
                  "FrameBufferInfo request ID and buffer sizes");
        TestCheck(words[0] == EXPECTED_INTEGER_TYPE &&
                  words[1] == expectedScreenNumber,
                  "FrameBufferInfo sends the screen number");
        replyID = 7301;
        successSize = 272;
    } else if (expectedOperation == TestAccessTokens) {
        TestCheck(sendSize == 64 && header->msg_size == 32 &&
                  header->msg_simple == 1 && header->msg_id == 7217,
                  "GetDeviceAccessTokens request ID and message sizes");
        TestCheck(words[0] == EXPECTED_INTEGER_TYPE &&
                  words[1] == expectedScreenNumber,
                  "GetDeviceAccessTokens sends the screen number");
        replyID = 7317;
        successSize = 64;
    } else if (expectedOperation == TestCompositeBits) {
        msg_type_long_t descriptor;
        int expectedByteCount = expectedCompositeFields[5] *
                                expectedCompositeFields[9];
        TestCheck(sendSize == 40 && header->msg_size == 112 &&
                  header->msg_simple == 0 && header->msg_id == 7200,
                  "CompositeBits request ID and message sizes");
        TestCheck(words[0] == EXPECTED_INTEGER_TYPE &&
                  words[1] == expectedCompositeFields[0] &&
                  words[2] == EXPECTED_INTEGER_TYPE &&
                  words[3] == expectedCompositeFields[1] &&
                  words[4] == EXPECTED_INTEGER_TYPE &&
                  words[5] == expectedCompositeFields[2] &&
                  words[6] == EXPECTED_INTEGER_TYPE &&
                  words[7] == expectedCompositeFields[3],
                  "CompositeBits sends window, origin, and operation fields");
        memcpy(&descriptor, &words[8], sizeof(descriptor));
        TestCheck(descriptor.msg_type_header.msg_type_inline == 0 &&
                  descriptor.msg_type_header.msg_type_longform == 1 &&
                  descriptor.msg_type_long_name == 8 &&
                  descriptor.msg_type_long_size == 8 &&
                  descriptor.msg_type_long_number == (unsigned int)expectedByteCount &&
                  (unsigned int)words[11] ==
                      (unsigned int)(unsigned long)expectedCompositeBits,
                  "CompositeBits describes its out-of-line pixel payload");
        TestCheck(words[12] == EXPECTED_INTEGER_TYPE &&
                  words[13] == expectedCompositeFields[4] &&
                  words[14] == EXPECTED_INTEGER_TYPE &&
                  words[15] == expectedCompositeFields[5] &&
                  words[16] == EXPECTED_INTEGER_TYPE &&
                  words[17] == expectedCompositeFields[6] &&
                  words[18] == EXPECTED_INTEGER_TYPE &&
                  words[19] == expectedCompositeFields[9] &&
                  words[20] == EXPECTED_INTEGER_TYPE &&
                  words[21] == expectedCompositeFields[8],
                  "CompositeBits sends dimensions, depth, stride, and color space");
        replyID = 7300;
        successSize = 40;
    } else if (expectedOperation == TestBM34ToBM35 ||
               expectedOperation == TestBM35ToBM34) {
        int requestID = expectedOperation == TestBM34ToBM35 ? 7199 : 7206;
        replyID = requestID + 100;
        successSize = 56;
        TestCheck(sendSize == 56 && header->msg_size == sizeof(msg_header_t) &&
                  header->msg_simple == 1 && header->msg_id == requestID,
                  "16-bit conversion-table RPC request ID and sizes");
    } else if (expectedOperation == TestBM256ToBM38 ||
               expectedOperation == TestBM38ToBM256) {
        int requestID = expectedOperation == TestBM256ToBM38 ? 7210 : 7211;
        replyID = requestID + 100;
        successSize = 48;
        TestCheck(sendSize == 48 && header->msg_size == sizeof(msg_header_t) &&
                  header->msg_simple == 1 && header->msg_id == requestID,
                  "8-bit conversion-table RPC request ID and sizes");
    } else {
        int requestID = expectedOperation == TestScreenCount ? 7207 :
                        expectedOperation == TestHideCursor ? 7208 : 7209;
        replyID = requestID + 100;
        successSize = 40;
        TestCheck(sendSize == 40 && header->msg_size == sizeof(msg_header_t) &&
                  header->msg_simple == 1 && header->msg_id == requestID,
                  "simple Window Server RPC request ID and header sizes");
    }

    if (expectedReply == TestSendFailure)
        return expectedSendResult;

    header->msg_simple =
        expectedOperation == TestBM34ToBM35 ||
        expectedOperation == TestBM35ToBM34 ||
        expectedOperation == TestBM256ToBM38 ||
        expectedOperation == TestBM38ToBM256 ||
        (expectedOperation == TestAccessTokens &&
         expectedReply != TestErrorReply &&
         expectedReply != TestShortReply) ? 0 : 1;
    header->msg_type = 0x100;
    header->msg_id = expectedReply == TestWrongReplyID ? replyID + 1 : replyID;
    if (expectedReply == TestShortReply) {
        header->msg_size = 28;
        words[0] = EXPECTED_INTEGER_TYPE;
        words[1] = 0;
        return 0;
    }
    if (expectedReply == TestErrorReply) {
        header->msg_size = 32;
        words[0] = EXPECTED_INTEGER_TYPE;
        words[1] = 6;
        return 0;
    }

    header->msg_size = successSize;
    words[0] = EXPECTED_INTEGER_TYPE;
    words[1] = 0;
    words[2] = EXPECTED_INTEGER_TYPE;
    words[3] = expectedOperationResult;
    if (expectedOperation == TestAddRect) {
        words[4] = EXPECTED_RECT_TYPE;
        memcpy(&words[5], &replyRectangle, sizeof(replyRectangle));
    } else if (expectedOperation == TestMapFrameBuffer) {
        words[2] = EXPECTED_INTEGER_TYPE;
        words[3] = expectedOperationResult;
        words[4] = EXPECTED_INTEGER_TYPE;
        words[5] = (int)expectedAddress;
    } else if (expectedOperation == TestFrameBufferInfo) {
        int field;
        words[2] = EXPECTED_INTEGER_TYPE;
        words[3] = expectedOperationResult;
        TestSetLongType(&words[4], 640);
        memcpy(&words[7], expectedDriver, sizeof(expectedDriver));
        for (field = 0; field < 7; field++) {
            words[27 + field * 2] = EXPECTED_INTEGER_TYPE;
            words[28 + field * 2] = expectedFrameBufferFields[field];
        }
        TestSetLongType(&words[41], 512);
        memcpy(&words[44], expectedPixelEncoding,
               sizeof(expectedPixelEncoding));
        words[60] = EXPECTED_INTEGER_TYPE;
        words[61] = expectedFrameBufferFields[7];
    } else if (expectedOperation == TestAccessTokens) {
        words[2] = EXPECTED_INTEGER_TYPE;
        words[3] = expectedOperationResult;
        words[4] = EXPECTED_PORT_TYPE;
        words[5] = (int)expectedMasterPort;
        words[6] = EXPECTED_INTEGER_TYPE;
        words[7] = expectedIOObjectNumber;
        words[8] = EXPECTED_PORT_TYPE;
        words[9] = (int)expectedDevicePort;
    } else if (expectedOperation == TestBM34ToBM35 ||
               expectedOperation == TestBM35ToBM34) {
        int count = expectedOperation == TestBM34ToBM35 ? 4096 : 32768;
        words[2] = EXPECTED_INTEGER_TYPE;
        TestSetOutOfLineLongType(&words[4], count);
        words[7] = (int)(unsigned long)expectedTableWords;
    } else if (expectedOperation == TestBM256ToBM38 ||
               expectedOperation == TestBM38ToBM256) {
        words[2] = EXPECTED_INTEGER_TYPE;
        words[4] = expectedOperation == TestBM256ToBM38 ?
                   EXPECTED_BM256_TO_BM38_TYPE : EXPECTED_BM38_TO_BM256_TYPE;
        words[5] = (int)(unsigned long)expectedTableWords;
    }
    return 0;
}

int InterceptorTestMsgSend(msg_header_t *header, int option, int timeout)
{
    int expectedID = expectedOperation == TestShowCursor ? 7218 :
                     expectedOperation == TestRepairPalette ? 7215 : 7216;
    TestCheck(option == 0 && timeout == 0 && header->msg_simple == 1 &&
              header->msg_size == sizeof(msg_header_t) &&
              header->msg_type == 0 &&
              header->msg_remote_port == expectedContextPort &&
              header->msg_local_port == PORT_NULL && header->msg_id == expectedID,
              "asynchronous screen notification header and destination");
    return expectedReply == TestSendFailure ? expectedSendResult : 0;
}

static void PrepareCall(int operation, int reply)
{
    expectedOperation = operation;
    expectedReply = reply;
    expectedSendResult = -100;
    expectedContextPort = 0x111;
    expectedReplyPort = 0x222;
    expectedNotifyPort = 0x333;
    expectedExceptionPort = 0x444;
    expectedUniqueID = 0x12345678;
    expectedRectangle.x = 10;
    expectedRectangle.y = 20;
    expectedRectangle.w = 30;
    expectedRectangle.h = 40;
    expectedRectangle.idNum = 50;
    expectedRectangle.wnum = 60;
    expectedRectangle.snum = 70;
    expectedRectangle.flags = 80;
    replyRectangle.x = 110;
    replyRectangle.y = 120;
    replyRectangle.w = 130;
    replyRectangle.h = 140;
    replyRectangle.idNum = 150;
    replyRectangle.wnum = 160;
    replyRectangle.snum = 170;
    replyRectangle.flags = 180;
    expectedOperationResult = 0;
    expectedScreenNumber = 2;
    expectedTaskPort = task_self();
    expectedAddress = 0x12340000;
    expectedMasterPort = 0x515;
    expectedIOObjectNumber = 0x616;
    expectedDevicePort = 0x717;
    memset(expectedDriver, 0, sizeof(expectedDriver));
    strcpy(expectedDriver, "TestFramebufferDriver");
    memset(expectedPixelEncoding, 0, sizeof(expectedPixelEncoding));
    strcpy(expectedPixelEncoding, "RRRRRRRRGGGGGGGGBBBBBBBB--------");
    expectedFrameBufferFields[0] = 3;
    expectedFrameBufferFields[1] = 4;
    expectedFrameBufferFields[2] = 1024;
    expectedFrameBufferFields[3] = 768;
    expectedFrameBufferFields[4] = 32;
    expectedFrameBufferFields[5] = 4096;
    expectedFrameBufferFields[6] = 2;
    expectedFrameBufferFields[7] = 0;
    memset(expectedCompositeBits, 0xA5, sizeof(expectedCompositeBits));
    expectedCompositeFields[0] = 60;
    expectedCompositeFields[1] = 11;
    expectedCompositeFields[2] = 12;
    expectedCompositeFields[3] = 1;
    expectedCompositeFields[4] = 8;
    expectedCompositeFields[5] = 4;
    expectedCompositeFields[6] = 2;
    expectedCompositeFields[8] = 3;
    expectedCompositeFields[9] = 16;
}

int main(void)
{
    void *handle = TestLoadSelectedFramework();
    InterceptorClientContext context;
    InterceptedRectangle rectangle;
    TestCheck(handle != 0, "loads explicitly selected framework");
    TestCheck(sizeof(msg_header_t) == 24 && sizeof(msg_type_long_t) == 12,
              "Mach header and long-form descriptor match the wire layout");
    TestCheck(sizeof(InterceptorClientContext) == 12,
              "client context has three 32-bit port fields");
    TestCheck(offsetof(InterceptorClientContext, contextPort) == 0 &&
              offsetof(InterceptorClientContext, replyPort) == 4 &&
              offsetof(InterceptorClientContext, notifyPort) == 8,
              "client context port order matches the wire contract");
    TestCheck(sizeof(InterceptedRectangle) == 32 &&
              offsetof(InterceptedRectangle, idNum) == 16 &&
              offsetof(InterceptedRectangle, flags) == 28,
              "rectangle request is eight contiguous 32-bit integers");
    TestCheck(sizeof(IntRect) == 16 && offsetof(IntRect, h) == 12,
              "clip rectangles use four 32-bit integers");
    TestCheck(sizeof(InterceptorNotification) == 108 &&
              offsetof(InterceptorNotification, sequenceNumber) == 28 &&
              offsetof(InterceptorNotification, args) == 44,
              "notification header and fixed integer payload match");
    TestCheck(sizeof(InterceptorReply) == 40 &&
              offsetof(InterceptorReply, replyCode) == 36,
              "notification reply layout matches the public contract");
    TestCheck(INTERCEPT_NOTIFY_MSGID == 1234 && INTERCEPT_REPLY_MSGID == 4321,
              "notification IDs remain separate from RPC request IDs");
    if (handle) {
        TestCheck(dlsym(handle, "_InterceptorAddRect") != 0,
                  "selected framework exports the AddRect RPC");
        TestCheck(dlsym(handle, "_InterceptorRemoveRect") != 0,
                  "selected framework exports the RemoveRect RPC");
        TestCheck(dlsym(handle, "_InterceptorSetNotifyPort") != 0,
                  "selected framework exports the SetNotifyPort RPC");
        TestCheck(dlsym(handle, "_InterceptorScreenCount") != 0 &&
                  dlsym(handle, "_InterceptorHideCursor") != 0 &&
                  dlsym(handle, "_InterceptorShowCursor") != 0,
                  "selected framework exports screen-count and cursor RPCs");
        TestCheck(dlsym(handle, "_InterceptorRepairPalette") != 0 &&
                  dlsym(handle, "_InterceptorDamagedPalette") != 0,
                  "selected framework exports palette notification RPCs");
        TestCheck(dlsym(handle, "_InterceptorMapFrameBuffer") != 0 &&
                  dlsym(handle, "_InterceptorUnmapFrameBuffer") != 0,
                  "selected framework exports framebuffer mapping RPCs");
        TestCheck(dlsym(handle, "_InterceptorFrameBufferInfo") != 0,
                  "selected framework exports framebuffer metadata RPC");
        TestCheck(dlsym(handle, "_InterceptorGetDeviceAccessTokens") != 0,
                  "selected framework exports device-access-token RPC");
        TestCheck(dlsym(handle, "InterceptorGetDeviceAccessTokens") != 0,
                  "selected framework exports the context token wrapper");
        TestCheck(dlsym(handle, "_InterceptorCompositeBits") != 0,
                  "selected framework exports the CompositeBits RPC");
        TestCheck(dlsym(handle, "_InterceptorGetBM34ToBM35Table") != 0 &&
                  dlsym(handle, "_InterceptorGetBM35ToBM34Table") != 0 &&
                  dlsym(handle, "_InterceptorGetBM256ToBM38Table") != 0 &&
                  dlsym(handle, "_InterceptorGetBM38ToBM256Table") != 0,
                  "selected framework exports all conversion-table RPCs");
        TestCheck(dlsym(handle, "InterceptorCreateContext") != 0,
                  "selected framework exports context creation");
        TestCheck(dlsym(handle, "InterceptorDestroyContext") != 0,
                  "selected framework exports context destruction");
    }

    PrepareCall(TestAddRect, TestSuccessReply);
    rectangle = expectedRectangle;
    TestCheck(_InterceptorAddRect(expectedContextPort, expectedReplyPort,
                                  &rectangle) == expectedOperationResult,
              "AddRect returns the successful operation result");
    TestCheck(memcmp(&rectangle, &replyRectangle, sizeof(rectangle)) == 0,
              "AddRect copies the eight returned integers");

    PrepareCall(TestRemoveRect, TestSuccessReply);
    TestCheck(_InterceptorRemoveRect(expectedContextPort, expectedReplyPort,
                                     expectedUniqueID) == expectedOperationResult,
              "RemoveRect accepts a valid success reply");

    PrepareCall(TestSetNotifyPort, TestSuccessReply);
    TestCheck(_InterceptorSetNotifyPort(expectedContextPort, expectedReplyPort,
                                        expectedNotifyPort,
                                        expectedExceptionPort) == expectedOperationResult,
              "SetNotifyPort accepts a valid success reply");

    PrepareCall(TestScreenCount, TestSuccessReply);
    expectedOperationResult = 3;
    TestCheck(_InterceptorScreenCount(expectedContextPort, expectedReplyPort) == 3,
              "ScreenCount returns the server's screen count");
    PrepareCall(TestHideCursor, TestSuccessReply);
    TestCheck(_InterceptorHideCursor(expectedContextPort, expectedReplyPort) == 0,
              "HideCursor accepts a valid success reply");
    PrepareCall(TestShowCursor, TestSuccessReply);
    TestCheck(_InterceptorShowCursor(expectedContextPort, expectedReplyPort) == 0,
              "ShowCursor accepts a valid success reply");
    PrepareCall(TestShowCursor, TestSuccessReply);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    context.notifyPort = PORT_NULL;
    TestCheck(InterceptorShowCursor(&context) == 0,
              "ShowCursor wrapper queues an asynchronous request");

    PrepareCall(TestRepairPalette, TestSuccessReply);
    TestCheck(_InterceptorRepairPalette(expectedContextPort) == 0,
              "RepairPalette queues its asynchronous request");
    PrepareCall(TestDamagedPalette, TestSuccessReply);
    context.contextPort = expectedContextPort;
    TestCheck(InterceptorDamagedPalette(&context) == 0,
              "DamagedPalette wrapper queues its asynchronous request");
    PrepareCall(TestRepairPalette, TestSendFailure);
    TestCheck(_InterceptorRepairPalette(expectedContextPort) ==
              expectedSendResult,
              "RepairPalette reports a failed asynchronous send");

    PrepareCall(TestMapFrameBuffer, TestSuccessReply);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    {
        void *address = 0;
        TestCheck(InterceptorMapFrameBuffer(&context, expectedScreenNumber,
                                            &address) == expectedOperationResult,
                  "MapFrameBuffer accepts a valid success reply");
        TestCheck((unsigned long)address == expectedAddress,
                  "MapFrameBuffer returns the mapped address");
    }

    PrepareCall(TestMapFrameBuffer, TestErrorReply);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    {
        void *address = 0;
        TestCheck(InterceptorMapFrameBuffer(&context, expectedScreenNumber,
                                            &address) != 0 && address == 0,
                  "MapFrameBuffer preserves an empty address on server error");
    }

    PrepareCall(TestMapFrameBuffer, TestWrongReplyID);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    {
        void *address = 0;
        TestCheck(InterceptorMapFrameBuffer(&context, expectedScreenNumber,
                                            &address) != 0 && address == 0,
                  "MapFrameBuffer rejects a reply with the wrong ID");
    }

    PrepareCall(TestMapFrameBuffer, TestShortReply);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    {
        void *address = 0;
        TestCheck(InterceptorMapFrameBuffer(&context, expectedScreenNumber,
                                            &address) != 0 && address == 0,
                  "MapFrameBuffer rejects an undersized success reply");
    }

    PrepareCall(TestUnmapFrameBuffer, TestSuccessReply);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    TestCheck(InterceptorUnmapFrameBuffer(&context, expectedScreenNumber,
                                          (void *)(unsigned long)expectedAddress) ==
              expectedOperationResult,
              "UnmapFrameBuffer accepts a valid success reply");

    PrepareCall(TestFrameBufferInfo, TestSuccessReply);
    {
        char driver[80];
        char pixelEncoding[64];
        int fields[8] = { 0 };
        memset(driver, 0, sizeof(driver));
        memset(pixelEncoding, 0, sizeof(pixelEncoding));
        TestCheck(InterceptorFrameBufferInfo(
                      &context, expectedScreenNumber, driver,
                      &fields[0], &fields[1], &fields[2], &fields[3],
                      &fields[4], &fields[5], &fields[6], pixelEncoding,
                      &fields[7]) == expectedOperationResult,
                  "FrameBufferInfo accepts the recovered success reply");
        TestCheck(memcmp(driver, expectedDriver, sizeof(driver)) == 0 &&
                  memcmp(pixelEncoding, expectedPixelEncoding,
                         sizeof(pixelEncoding)) == 0,
                  "FrameBufferInfo returns driver and pixel encoding strings");
        TestCheck(memcmp(fields, expectedFrameBufferFields, sizeof(fields)) == 0,
                  "FrameBufferInfo returns all metadata fields in order");
    }

    PrepareCall(TestAccessTokens, TestSuccessReply);
    expectedOperationResult = 23;
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    {
        port_t masterPort = PORT_NULL;
        int ioObjectNumber = -1;
        port_t devicePort = PORT_NULL;
        TestCheck(InterceptorGetDeviceAccessTokens(
                      &context, expectedScreenNumber, &masterPort,
                  &ioObjectNumber, &devicePort) == expectedOperationResult,
                  "GetDeviceAccessTokens accepts a valid success reply");
        TestCheck(masterPort == expectedMasterPort &&
                  ioObjectNumber == expectedIOObjectNumber &&
                  devicePort == expectedDevicePort,
                  "GetDeviceAccessTokens returns all three values in order");
    }

    PrepareCall(TestAccessTokens, TestWrongReplyID);
    expectedOperationResult = 23;
    {
        port_t masterPort = 0xA1;
        int ioObjectNumber = 0xA2;
        port_t devicePort = 0xA3;
        TestCheck(_InterceptorGetDeviceAccessTokens(
                      expectedContextPort, expectedReplyPort,
                      expectedScreenNumber, &masterPort, &ioObjectNumber,
                      &devicePort) == expectedOperationResult,
                  "GetDeviceAccessTokens reports the reply operation word after a wrong ID");
        TestCheck(masterPort == 0xA1 && ioObjectNumber == 0xA2 &&
                  devicePort == 0xA3,
                  "GetDeviceAccessTokens leaves outputs untouched on invalid reply");
    }

    PrepareCall(TestAccessTokens, TestErrorReply);
    TestCheck(_InterceptorGetDeviceAccessTokens(
                  expectedContextPort, expectedReplyPort, expectedScreenNumber,
                  &expectedMasterPort, &expectedIOObjectNumber,
                  &expectedDevicePort) == 0,
              "GetDeviceAccessTokens retains its zero return word for short server errors");

    PrepareCall(TestCompositeBits, TestSuccessReply);
    context.contextPort = expectedContextPort;
    context.replyPort = expectedReplyPort;
    TestCheck(InterceptorCompositeBits(
                  &context, expectedCompositeFields[0],
                  expectedCompositeFields[1], expectedCompositeFields[2],
                  expectedCompositeFields[3], expectedCompositeBits,
                  expectedCompositeFields[4], expectedCompositeFields[5],
                  expectedCompositeFields[6], expectedCompositeFields[9],
                  expectedCompositeFields[8]) == 0,
              "CompositeBits accepts the recovered success reply");

    PrepareCall(TestFrameBufferInfo, TestWrongReplyID);
    {
        char driver[80];
        char pixelEncoding[64];
        int fields[8];
        memset(driver, 0x5A, sizeof(driver));
        memset(pixelEncoding, 0x5A, sizeof(pixelEncoding));
        memset(fields, 0x5A, sizeof(fields));
        (void)_InterceptorFrameBufferInfo(
            expectedContextPort, expectedReplyPort, expectedScreenNumber,
            driver, &fields[0], &fields[1], &fields[2], &fields[3],
            &fields[4], &fields[5], &fields[6], pixelEncoding, &fields[7]);
        TestCheck((unsigned char)driver[0] == 0x5A &&
                  (unsigned char)pixelEncoding[0] == 0x5A &&
                  (unsigned char)fields[0] == 0x5A,
                  "FrameBufferInfo leaves outputs untouched for a wrong reply ID");
    }

    PrepareCall(TestFrameBufferInfo, TestErrorReply);
    {
        char driver[80];
        char pixelEncoding[64];
        int fields[8];
        memset(driver, 0x5A, sizeof(driver));
        memset(pixelEncoding, 0x5A, sizeof(pixelEncoding));
        memset(fields, 0x5A, sizeof(fields));
        (void)_InterceptorFrameBufferInfo(
            expectedContextPort, expectedReplyPort, expectedScreenNumber,
            driver, &fields[0], &fields[1], &fields[2], &fields[3],
            &fields[4], &fields[5], &fields[6], pixelEncoding, &fields[7]);
        TestCheck((unsigned char)driver[0] == 0x5A &&
                  (unsigned char)pixelEncoding[0] == 0x5A &&
                  (unsigned char)fields[0] == 0x5A,
                  "FrameBufferInfo leaves outputs untouched for a server error");
    }

    PrepareCall(TestFrameBufferInfo, TestShortReply);
    {
        char driver[80];
        char pixelEncoding[64];
        int fields[8];
        memset(driver, 0x5A, sizeof(driver));
        memset(pixelEncoding, 0x5A, sizeof(pixelEncoding));
        memset(fields, 0x5A, sizeof(fields));
        (void)_InterceptorFrameBufferInfo(
            expectedContextPort, expectedReplyPort, expectedScreenNumber,
            driver, &fields[0], &fields[1], &fields[2], &fields[3],
            &fields[4], &fields[5], &fields[6], pixelEncoding, &fields[7]);
        TestCheck((unsigned char)driver[0] == 0x5A &&
                  (unsigned char)pixelEncoding[0] == 0x5A &&
                  (unsigned char)fields[0] == 0x5A,
                  "FrameBufferInfo leaves outputs untouched for a short reply");
    }

    PrepareCall(TestBM34ToBM35, TestSuccessReply);
    {
        void *table = 0;
        TestCheck(_InterceptorGetBM34ToBM35Table(
                      expectedContextPort, expectedReplyPort, &table) == 0 &&
                  table == expectedTableWords,
                  "BM34-to-BM35 returns the 4096-entry out-of-line table");
    }
    PrepareCall(TestBM35ToBM34, TestSuccessReply);
    {
        void *table = 0;
        TestCheck(_InterceptorGetBM35ToBM34Table(
                      expectedContextPort, expectedReplyPort, &table) == 0 &&
                  table == expectedTableWords,
                  "BM35-to-BM34 returns the 32768-entry out-of-line table");
    }
    PrepareCall(TestBM256ToBM38, TestSuccessReply);
    {
        void *table = 0;
        TestCheck(_InterceptorGetBM256ToBM38Table(
                      expectedContextPort, expectedReplyPort, &table) == 0 &&
                  table == expectedTableWords,
                  "BM256-to-BM38 accepts the recovered byte-table descriptor");
    }
    PrepareCall(TestBM38ToBM256, TestSuccessReply);
    {
        void *table = 0;
        TestCheck(_InterceptorGetBM38ToBM256Table(
                      expectedContextPort, expectedReplyPort, &table) == 0 &&
                  table == expectedTableWords,
                  "BM38-to-BM256 accepts the recovered byte-table descriptor");
    }
    PrepareCall(TestBM34ToBM35, TestErrorReply);
    {
        void *table = (void *)1;
        (void)_InterceptorGetBM34ToBM35Table(
            expectedContextPort, expectedReplyPort, &table);
        TestCheck(table == (void *)1,
                  "failed long-form table RPC leaves its output untouched");
    }
    PrepareCall(TestBM256ToBM38, TestShortReply);
    {
        void *table = (void *)1;
        (void)_InterceptorGetBM256ToBM38Table(
            expectedContextPort, expectedReplyPort, &table);
        TestCheck(table == (void *)1,
                  "short byte-table reply leaves its output untouched");
    }

    PrepareCall(TestAddRect, TestErrorReply);
    rectangle = expectedRectangle;
    TestCheck(_InterceptorAddRect(expectedContextPort, expectedReplyPort,
                                  &rectangle) == expectedRectangle.w,
              "AddRect retains its in/out result word for a server error reply");

    PrepareCall(TestRemoveRect, TestWrongReplyID);
    TestCheck(_InterceptorRemoveRect(expectedContextPort, expectedReplyPort,
                                     expectedUniqueID) == 0,
              "RemoveRect rejects a reply with the wrong ID");

    PrepareCall(TestAddRect, TestShortReply);
    rectangle = expectedRectangle;
    TestCheck(_InterceptorAddRect(expectedContextPort, expectedReplyPort,
                                  &rectangle) == expectedRectangle.w,
              "AddRect rejects an undersized success reply");

    PrepareCall(TestSetNotifyPort, TestSendFailure);
    TestCheck(_InterceptorSetNotifyPort(expectedContextPort, expectedReplyPort,
                                        expectedNotifyPort,
                                        expectedExceptionPort) == expectedExceptionPort,
              "SetNotifyPort retains its in/out result word on send failure");
    return TestFinish();
}
