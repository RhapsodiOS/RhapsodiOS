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
       TestMapFrameBuffer, TestUnmapFrameBuffer, TestFrameBufferInfo };
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
static char expectedDriver[80];
static char expectedPixelEncoding[64];
static int expectedFrameBufferFields[8];

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

    header->msg_simple = 1;
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
    }
    return 0;
}

int InterceptorTestMsgSend(msg_header_t *header, int option, int timeout)
{
    TestCheck(option == 0 && timeout == 0 && header->msg_simple == 1 &&
              header->msg_size == sizeof(msg_header_t) &&
              header->msg_type == 0 &&
              header->msg_remote_port == expectedContextPort &&
              header->msg_local_port == PORT_NULL && header->msg_id == 7218,
              "asynchronous ShowCursor request header and destination");
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
        TestCheck(dlsym(handle, "_InterceptorMapFrameBuffer") != 0 &&
                  dlsym(handle, "_InterceptorUnmapFrameBuffer") != 0,
                  "selected framework exports framebuffer mapping RPCs");
        TestCheck(dlsym(handle, "_InterceptorFrameBufferInfo") != 0,
                  "selected framework exports framebuffer metadata RPC");
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
