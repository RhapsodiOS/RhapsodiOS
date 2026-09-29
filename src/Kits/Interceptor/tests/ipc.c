#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Interceptor_types.h"
#include "test_support.h"

int main(void)
{
    void *handle = TestLoadSelectedFramework();
    TestCheck(handle != 0, "loads explicitly selected framework");
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
        TestCheck(dlsym(handle, "InterceptorCreateContext") != 0,
                  "selected framework exports context creation");
    }
    return TestFinish();
}
