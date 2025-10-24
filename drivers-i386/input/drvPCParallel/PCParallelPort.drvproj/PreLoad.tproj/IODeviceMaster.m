/*
 * IODeviceMaster.m - Device Master interface wrapper implementation
 *
 * Implementation for IODeviceMaster interface.
 */

#import "IODeviceMaster.h"
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <stdio.h>
#import <string.h>

// External kernel functions
extern port_t device_master_self(void);

// Mach IPC functions
extern mach_port_t mig_get_reply_port(void);
extern void mig_dealloc_reply_port(mach_port_t port);
extern kern_return_t msg_rpc(void *msg, int option, int send_size, int rcv_size, int timeout);

// Utility function for device method calls
int __IOCallDeviceMethod(port_t masterPort, int objNum, unsigned int *inStruct,
                         void *inData, unsigned int inDataCount,
                         unsigned int *outResult, void *outData, unsigned int *outDataCount)
{
    kern_return_t result;
    unsigned int alignedSize;
    mach_port_t replyPort;
    int i;

    // Mach message buffer - send and receive use same buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
            int inputHeader2;
            unsigned int inStructData[20];  // 80 bytes
            unsigned int dataDescriptor;
            unsigned int dataBuffer[514];   // Up to 0x800 bytes
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int resultValue;
            unsigned int outDataDescriptor;
            unsigned char outDataBuffer[2048];
        } rcv;
    } msg;

    // Validate input data size
    if (inDataCount >= 0x801) {
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }

    // Initialize send message headers
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;
    msg.send.inputHeader2 = 0x10500808;

    // Copy input structure (20 dwords = 80 bytes)
    for (i = 0; i < 20; i++) {
        msg.send.inStructData[i] = inStruct[i];
    }

    // Set data descriptor and copy data
    msg.send.dataDescriptor = 0x18000808;
    bcopy(inData, msg.send.dataBuffer, inDataCount);

    // Update descriptor with actual data size
    msg.send.dataDescriptor = (msg.send.dataDescriptor & 0xF000FFFF) |
                               ((inDataCount & 0xFFF) << 16);

    // Calculate aligned size and add tail
    alignedSize = (inDataCount + 3) & 0xFFFFFFFC;
    *(int *)((char *)msg.send.dataBuffer + alignedSize) = 0x10012002;
    *(unsigned int *)((char *)msg.send.dataBuffer + alignedSize + 4) = *outResult;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = alignedSize + 0x80;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xab3;  // 2739

    // Send message and receive reply (buffer reused)
    result = msg_rpc(&msg.send.pad[0], 0, 0x82c, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message (now in same buffer)
    if (msg.rcv.msgId != 0xb17) {  // 2839
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize - 0x2c >= 0x801) || msg.rcv.msgBits != 0x01) {
        if (msg.rcv.msgSize != 0x20 || msg.rcv.msgBits != 0x01 ||
            msg.rcv.returnCode == 0) {
            return -300;  // Invalid reply structure
        }
    }

    if (msg.rcv.resultHeader1 != 0x10012002) {
        return -300;
    }

    // Check for error return
    if (msg.rcv.returnCode != 0) {
        return msg.rcv.returnCode;
    }

    // Validate and extract results
    if (msg.rcv.resultHeader2 != 0x10012002) {
        return -300;
    }

    *outResult = msg.rcv.resultValue;

    if ((msg.rcv.outDataDescriptor & 0x3000FFFF) != 0x10000808) {
        return -300;
    }

    // Extract output data size
    unsigned int actualOutSize = (msg.rcv.outDataDescriptor >> 16) & 0xFFF;

    // Verify message size matches
    if (msg.rcv.msgSize != ((actualOutSize + 3) & 0xFFFFFFFC) + 0x2c) {
        return -300;
    }

    // Copy output data
    if (actualOutSize <= *outDataCount) {
        bcopy(msg.rcv.outDataBuffer, outData, actualOutSize);
        *outDataCount = actualOutSize;
        return msg.rcv.returnCode;
    }

    // Output buffer too small - copy what fits and return error
    bcopy(msg.rcv.outDataBuffer, outData, *outDataCount);
    *outDataCount = actualOutSize;
    return -0x133;  // MIG_ARRAY_TOO_LARGE
}

// Create Mach port for IO device
int __IOCreateMachPort(port_t masterPort, int objNum, port_t *outPort)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            int portDescriptor;
            port_t resultPort;
        } rcv;
    } msg;

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x20;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xab4;  // 2740

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x28, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb18) {  // 2840
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize == 0x28 && msg.rcv.msgBits == 0x00) ||
        (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 && msg.rcv.returnCode != 0)) {

        if (msg.rcv.resultHeader1 != 0x10012002) {
            return -300;
        }

        // Check for error return
        if (msg.rcv.returnCode != 0) {
            return msg.rcv.returnCode;
        }

        // Extract port from reply
        if (msg.rcv.portDescriptor == 0x10012006) {
            *outPort = msg.rcv.resultPort;
            return 0;
        }
    }

    return -300;  // Invalid reply structure
}

// Set character array values for device parameter
int __IOSetCharValues(port_t masterPort, int objNum, unsigned int *paramName,
                      const char *values, unsigned int count)
{
    kern_return_t result;
    mach_port_t replyPort;
    int i;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
            unsigned int paramDescriptor;
            unsigned int paramNameData[16];  // 64 bytes for parameter name
            unsigned int dataDescriptor;
            unsigned char dataBuffer[512];
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Validate data size
    if (count >= 0x201) {
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;
    msg.send.paramDescriptor = 0x10400808;

    // Copy parameter name (16 dwords = 64 bytes)
    for (i = 0; i < 16; i++) {
        msg.send.paramNameData[i] = paramName[i];
    }

    // Set data descriptor and copy data
    msg.send.dataDescriptor = 0x12000808;
    bcopy(values, msg.send.dataBuffer, count);

    // Update descriptor with actual data size
    msg.send.dataDescriptor = (msg.send.dataDescriptor & 0xF000FFFF) |
                              ((count & 0xFFF) << 16);

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = ((count + 3) & 0xFFFFFFFC) + 0x68;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa3;  // 2723

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb07) {  // 2823
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Set integer array values for device parameter
int __IOSetIntValues(port_t masterPort, int objNum, unsigned int *paramName,
                     const unsigned int *values, unsigned int count)
{
    kern_return_t result;
    mach_port_t replyPort;
    int i;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
            unsigned int paramDescriptor;
            unsigned int paramNameData[16];  // 64 bytes for parameter name
            unsigned int dataDescriptor;
            unsigned int dataBuffer[2048];  // Up to 512 integers
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Validate data size (count is in integers, max 0x200)
    if (count >= 0x201) {
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;
    msg.send.paramDescriptor = 0x10400808;

    // Copy parameter name (16 dwords = 64 bytes)
    for (i = 0; i < 16; i++) {
        msg.send.paramNameData[i] = paramName[i];
    }

    // Set data descriptor and copy data
    msg.send.dataDescriptor = 0x12002002;
    bcopy(values, msg.send.dataBuffer, count * 4);  // count * 4 for bytes

    // Update descriptor with actual integer count
    msg.send.dataDescriptor = (msg.send.dataDescriptor & 0xF000FFFF) |
                              ((count & 0xFFF) << 16);

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = (count * 4) + 0x68;  // count * 4 for byte size
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa2;  // 2722

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb06) {  // 2822
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Lookup device by name
int __IOLookupByDeviceName(port_t masterPort, const char *deviceName,
                           int *objNum, const char **kind)
{
    kern_return_t result;
    mach_port_t replyPort;
    int i;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int nameDescriptor;
            int nameData[20];  // 80 bytes for device name
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int objectNumber;
            int kindDescriptor1;
            int kindDescriptor2;
            int kindData[20];  // 80 bytes for device kind
        } rcv;
    } msg;

    // Initialize send message
    msg.send.nameDescriptor = 0x10500808;

    // Copy device name (20 dwords = 80 bytes)
    for (i = 0; i < 20; i++) {
        msg.send.nameData[i] = ((int *)deviceName)[i];
    }

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x6c;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xa9f;  // 2719

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x7c, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb03) {  // 2819
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize == 0x7c && msg.rcv.msgBits == 0x01) ||
        (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 && msg.rcv.returnCode != 0)) {

        if (msg.rcv.resultHeader1 != 0x10012002) {
            return -300;
        }

        // Check for error return
        if (msg.rcv.returnCode != 0) {
            return msg.rcv.returnCode;
        }

        // Extract object number
        if (msg.rcv.kindDescriptor1 != 0x10012002) {
            return -300;
        }
        *objNum = msg.rcv.objectNumber;

        // Extract device kind
        if (msg.rcv.kindDescriptor2 != 0x10500808) {
            return -300;
        }

        // Copy kind data (20 dwords = 80 bytes)
        for (i = 0; i < 20; i++) {
            ((int *)kind)[i] = msg.rcv.kindData[i];
        }

        return 0;
    }

    return -300;
}

// Lookup device by object number
int __IOLookupByObjectNumber(port_t masterPort, int objNum,
                             const char **kind, char **name)
{
    kern_return_t result;
    mach_port_t replyPort;
    int i;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int kindDescriptor;
            int kindData[20];      // 80 bytes for device kind
            int nameDescriptor;
            int nameData[20];      // 80 bytes for device name
        } rcv;
    } msg;

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x20;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xa9e;  // 2718

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 200, 0, 0);  // 200 = 0xc8

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb02) {  // 2818
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize == 200 && msg.rcv.msgBits == 0x01) ||
        (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 && msg.rcv.returnCode != 0)) {

        if (msg.rcv.resultHeader1 != 0x10012002) {
            return -300;
        }

        // Check for error return
        if (msg.rcv.returnCode != 0) {
            return msg.rcv.returnCode;
        }

        // Extract device kind
        if (msg.rcv.kindDescriptor != 0x10500808) {
            return -300;
        }

        // Copy kind data (20 dwords = 80 bytes)
        for (i = 0; i < 20; i++) {
            ((int *)kind)[i] = msg.rcv.kindData[i];
        }

        // Extract device name
        if (msg.rcv.nameDescriptor != 0x10500808) {
            return -300;
        }

        // Copy name data (20 dwords = 80 bytes)
        for (i = 0; i < 20; i++) {
            ((int *)name)[i] = msg.rcv.nameData[i];
        }

        return 0;
    }

    return -300;
}

// Map EISA device memory
int __IOMapEISADeviceMemory(port_t masterPort, int objNum,
                            unsigned int address1, unsigned int address2,
                            unsigned int *inOutSize, unsigned char flags,
                            unsigned int param7)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int objNumDescriptor;
            int objectNumber;
            int address1Descriptor;
            unsigned int addressValue1;
            int address2Descriptor;
            unsigned int addressValue2;
            int sizeDescriptor;
            unsigned int sizeValue;
            int flagsDescriptor;
            unsigned char flagsValue;
            int param7Descriptor;
            unsigned int param7Value;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int resultSize;
        } rcv;
    } msg;

    // Initialize send message
    msg.send.objNumDescriptor = 0x10012006;
    msg.send.objectNumber = objNum;
    msg.send.address1Descriptor = 0x10012002;
    msg.send.addressValue1 = address1;
    msg.send.address2Descriptor = 0x10012002;
    msg.send.addressValue2 = address2;
    msg.send.sizeDescriptor = 0x10012002;
    msg.send.sizeValue = *inOutSize;
    msg.send.flagsDescriptor = 0x10010808;
    msg.send.flagsValue = flags;
    msg.send.param7Descriptor = 0x10012002;
    msg.send.param7Value = param7;

    // Set up Mach message header
    msg.send.msgBits = 0x00;  // Note: msgBits is 0 for this call
    msg.send.msgSize = 0x48;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa7;  // 2727

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x28, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb0b) {  // 2827
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize == 0x28 && msg.rcv.msgBits == 0x01) ||
        (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 && msg.rcv.returnCode != 0)) {

        if (msg.rcv.resultHeader1 != 0x10012002) {
            return -300;
        }

        // Check for error return
        if (msg.rcv.returnCode != 0) {
            return msg.rcv.returnCode;
        }

        // Extract result size
        if (msg.rcv.resultHeader2 != 0x10012002) {
            return -300;
        }
        *inOutSize = msg.rcv.resultSize;

        return 0;
    }

    return -300;
}

// Map EISA device ports
int __IOMapEISADevicePorts(port_t masterPort, int objNum)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int objNumDescriptor;
            int objectNumber;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Initialize send message
    msg.send.objNumDescriptor = 0x10012006;
    msg.send.objectNumber = objNum;

    // Set up Mach message header
    msg.send.msgBits = 0x00;  // Note: msgBits is 0 for this call
    msg.send.msgSize = 0x20;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa5;  // 2725

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb09) {  // 2825
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Probe driver with configuration data
int __IOProbeDriver(port_t masterPort, void *configData, unsigned int dataSize)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int dataHeader1;
            int dataDescriptor;
            unsigned int actualSize;
            unsigned char dataBuffer[4096];
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Validate data size
    if (dataSize >= 0x1001) {
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }

    // Initialize send message
    msg.send.dataHeader1 = 0x30000000;
    msg.send.dataDescriptor = 0x80008;
    msg.send.actualSize = 0x1000;

    // Copy configuration data
    bcopy(configData, msg.send.dataBuffer, dataSize);
    msg.send.actualSize = dataSize;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = ((dataSize + 3) & 0xFFFFFFFC) + 0x24;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaaa;  // 2730

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb0e) {  // 2830
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Unload driver with configuration data
int __IOUnloadDriver(port_t masterPort, void *configData, unsigned int dataSize)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int dataHeader1;
            int dataDescriptor;
            unsigned int actualSize;
            unsigned char dataBuffer[4096];
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Validate data size
    if (dataSize >= 0x1001) {
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }

    // Initialize send message
    msg.send.dataHeader1 = 0x30000000;
    msg.send.dataDescriptor = 0x80008;
    msg.send.actualSize = 0x1000;

    // Copy configuration data
    bcopy(configData, msg.send.dataBuffer, dataSize);
    msg.send.actualSize = dataSize;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = ((dataSize + 3) & 0xFFFFFFFC) + 0x24;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaac;  // 2732

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb10) {  // 2832
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Unmap EISA device ports
int __IOUnMapEISADevicePorts(port_t masterPort, int objNum)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int objNumDescriptor;
            int objectNumber;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Initialize send message
    msg.send.objNumDescriptor = 0x10012006;
    msg.send.objectNumber = objNum;

    // Set up Mach message header
    msg.send.msgBits = 0x00;  // Note: msgBits is 0 for this call
    msg.send.msgSize = 0x20;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa6;  // 2726

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb0a) {  // 2826
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Get EISA device configuration (4 output arrays)
int __IOGetEISADeviceConfig(port_t masterPort,
                            void *array1, unsigned int *count1,
                            void *array2, unsigned int *count2,
                            void *array3, unsigned int *count3,
                            void *array4, unsigned int *count4)
{
    kern_return_t result;
    mach_port_t replyPort;
    size_t size1, size2, size3, size4;
    unsigned int cnt1, cnt2, cnt3, cnt4;
    unsigned short descWord;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            unsigned int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
        } send;
        struct {
            char pad[3];
            char msgBits;
            unsigned int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int descriptor1;
            unsigned short data[282];  // Combined buffer for all 4 arrays
        } rcv;
    } msg;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x18;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa4;  // 2724

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x144, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb08) {  // 2824
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize - 0x30 >= 0x115) || msg.rcv.msgBits != 0x01) {
        if (msg.rcv.msgSize != 0x20 || msg.rcv.msgBits != 0x01 || msg.rcv.returnCode == 0) {
            return -300;
        }
    }

    if (msg.rcv.resultHeader1 != 0x10012002) {
        return -300;
    }

    // Check for error return
    if (msg.rcv.returnCode != 0) {
        return msg.rcv.returnCode;
    }

    // Validate and extract first array (integers)
    if ((msg.rcv.descriptor1 & 0x3000FFFF) != 0x10002002) {
        return -300;
    }

    cnt1 = (msg.rcv.descriptor1 >> 16) & 0xFFF;
    size1 = cnt1 * 4;

    if (size1 + 0x30 > msg.rcv.msgSize) {
        return -300;
    }

    // Copy first array
    if (*count1 < cnt1) {
        bcopy(&msg.rcv.data[0], array1, (*count1) << 2);
        *count1 = cnt1;
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }
    bcopy(&msg.rcv.data[0], array1, size1);
    *count1 = cnt1;

    // Validate and extract second array (integers)
    unsigned int *desc2 = (unsigned int *)((char *)&msg.rcv.data[0] + size1);
    if ((*desc2 & 0x3000FFFF) != 0x10002002) {
        return -300;
    }

    descWord = *((unsigned short *)desc2 + 1);
    cnt2 = descWord & 0xFFF;
    size2 = cnt2 * 4;

    if (size2 + size1 + 0x30 > msg.rcv.msgSize) {
        return -300;
    }

    // Copy second array
    if (*count2 < cnt2) {
        bcopy((char *)desc2 + 4, array2, (*count2) << 2);
        *count2 = cnt2;
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }
    bcopy((char *)desc2 + 4, array2, size2);
    *count2 = cnt2;

    // Validate and extract third array (pairs - divide by 2)
    unsigned int *desc3 = (unsigned int *)((char *)desc2 + 4 + size2);
    if ((*desc3 & 0x3000FFFF) != 0x10002002) {
        return -300;
    }

    descWord = *((unsigned short *)desc3 + 1);
    cnt3 = (descWord & 0xFFF) >> 1;  // Divide by 2 for pairs
    size3 = (descWord & 0xFFF) * 4;

    if (size3 + size2 + size1 + 0x30 > msg.rcv.msgSize) {
        return -300;
    }

    // Copy third array
    if (*count3 < cnt3) {
        bcopy((char *)desc3 + 4, array3, (*count3) * 8);
        *count3 = cnt3;
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }
    bcopy((char *)desc3 + 4, array3, size3);
    *count3 = cnt3;

    // Validate and extract fourth array (pairs - divide by 2)
    unsigned int *desc4 = (unsigned int *)((char *)desc3 + 4 + size3);
    if ((*desc4 & 0x3000FFFF) != 0x10002002) {
        return -300;
    }

    descWord = *((unsigned short *)desc4 + 1);
    cnt4 = (descWord & 0xFFF) >> 1;  // Divide by 2 for pairs
    size4 = (descWord & 0xFFF) * 4;

    // Verify total message size
    if (msg.rcv.msgSize != size4 + size3 + size2 + size1 + 0x30) {
        return -300;
    }

    // Copy fourth array
    if (*count4 < cnt4) {
        bcopy((char *)desc4 + 4, array4, (*count4) * 8);
        *count4 = cnt4;
        return -0x133;  // MIG_ARRAY_TOO_LARGE
    }
    bcopy((char *)desc4 + 4, array4, size4);
    *count4 = cnt4;

    return msg.rcv.returnCode;
}

// Get system configuration data
int __IOGetSystemConfig(port_t masterPort, int objNum, void *outData, unsigned int *dataSize)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned char header2Byte3;  // Byte 3 of resultHeader2 for validation
            int dataDescriptor;
            unsigned int actualSize;
            unsigned char dataBuffer[4096];
        } rcv;
    } msg;

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x20;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaab;  // 2731

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x102c, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb0f) {  // 2831
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize - 0x2c >= 0x1001) || msg.rcv.msgBits != 0x01) {
        if (msg.rcv.msgSize != 0x20 || msg.rcv.msgBits != 0x01 ||
            msg.rcv.returnCode == 0) {
            return -300;
        }
    }

    if (msg.rcv.resultHeader1 != 0x10012002) {
        return -300;
    }

    // Check for error return
    if (msg.rcv.returnCode != 0) {
        return msg.rcv.returnCode;
    }

    // Validate descriptor - check bits 4-5 of byte 3 are both set (0x30)
    if ((msg.rcv.header2Byte3 & 0x30) != 0x30) {
        return -300;
    }

    // Validate data descriptor value
    if (msg.rcv.dataDescriptor != 0x80008) {
        return -300;
    }

    // Verify message size matches
    if (msg.rcv.msgSize != ((msg.rcv.actualSize + 3) & 0xFFFFFFFC) + 0x2c) {
        return -300;
    }

    // Copy output data
    if (msg.rcv.actualSize <= *dataSize) {
        bcopy(msg.rcv.dataBuffer, outData, msg.rcv.actualSize);
        *dataSize = msg.rcv.actualSize;
        return msg.rcv.returnCode;
    }

    // Output buffer too small - copy what fits and return error
    bcopy(msg.rcv.dataBuffer, outData, *dataSize);
    *dataSize = msg.rcv.actualSize;
    return -0x133;  // MIG_ARRAY_TOO_LARGE
}

// Get driver configuration data
int __IOGetDriverConfig(port_t masterPort, int objNum, int configType,
                        void *outData, unsigned int *dataSize)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
            int configTypeHeader;
            int configTypeValue;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            int dataDescriptor;
            unsigned int actualSize;
            unsigned char dataBuffer[4096];
        } rcv;
    } msg;

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;
    msg.send.configTypeHeader = 0x10012002;
    msg.send.configTypeValue = configType;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x28;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaad;  // 2733

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x102c, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb11) {  // 2833
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize - 0x2c >= 0x1001) || msg.rcv.msgBits != 0x01) {
        if (msg.rcv.msgSize != 0x20 || msg.rcv.msgBits != 0x01 ||
            msg.rcv.returnCode == 0) {
            return -300;
        }
    }

    if (msg.rcv.resultHeader1 != 0x10012002) {
        return -300;
    }

    // Check for error return
    if (msg.rcv.returnCode != 0) {
        return msg.rcv.returnCode;
    }

    // Validate descriptor - check bits 4-5 of byte 3 are both set (0x30)
    if (((msg.rcv.resultHeader2 >> 24) & 0x30) != 0x30) {
        return -300;
    }

    // Validate data descriptor value
    if (msg.rcv.dataDescriptor != 0x80008) {
        return -300;
    }

    // Verify message size matches
    if (msg.rcv.msgSize != ((msg.rcv.actualSize + 3) & 0xFFFFFFFC) + 0x2c) {
        return -300;
    }

    // Copy output data
    if (msg.rcv.actualSize <= *dataSize) {
        bcopy(msg.rcv.dataBuffer, outData, msg.rcv.actualSize);
        *dataSize = msg.rcv.actualSize;
        return msg.rcv.returnCode;
    }

    // Output buffer too small - copy what fits and return error
    bcopy(msg.rcv.dataBuffer, outData, *dataSize);
    *dataSize = msg.rcv.actualSize;
    return -0x133;  // MIG_ARRAY_TOO_LARGE
}

// Get integer array values from device parameter
int __IOGetIntValues(port_t masterPort, int objNum, unsigned int *paramName,
                     unsigned int maxCount, unsigned int *outValues, unsigned int *actualCount)
{
    kern_return_t result;
    mach_port_t replyPort;
    int i;
    unsigned int intCount;
    size_t byteCount;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
            unsigned int paramDescriptor;
            unsigned int paramNameData[16];  // 64 bytes for parameter name
            int maxCountHeader;
            unsigned int maxCountValue;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int dataDescriptor;
            unsigned int dataBuffer[512];
        } rcv;
    } msg;

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;
    msg.send.paramDescriptor = 0x10400808;

    // Copy parameter name (16 dwords = 64 bytes)
    for (i = 0; i < 16; i++) {
        msg.send.paramNameData[i] = paramName[i];
    }

    msg.send.maxCountHeader = 0x10012002;
    msg.send.maxCountValue = maxCount;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x6c;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa0;  // 2720

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x824, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb04) {  // 2820
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize - 0x24 >= 0x801) || msg.rcv.msgBits != 0x01) {
        if (msg.rcv.msgSize != 0x20 || msg.rcv.msgBits != 0x01 || msg.rcv.returnCode == 0) {
            return -300;
        }
    }

    if (msg.rcv.resultHeader1 != 0x10012002) {
        return -300;
    }

    // Check for error return
    if (msg.rcv.returnCode != 0) {
        return msg.rcv.returnCode;
    }

    // Validate and extract data - note 0x10002002 for integers (not 0x10000808 for chars)
    if ((msg.rcv.dataDescriptor & 0x3000FFFF) != 0x10002002) {
        return -300;
    }

    // Extract integer count (not byte count)
    intCount = (msg.rcv.dataDescriptor >> 16) & 0xFFF;
    byteCount = intCount * 4;

    // Verify message size matches
    if (msg.rcv.msgSize != byteCount + 0x24) {
        return -300;
    }

    // Copy output data
    if (intCount <= *actualCount) {
        bcopy(msg.rcv.dataBuffer, outValues, byteCount);
        *actualCount = intCount;
        return msg.rcv.returnCode;
    }

    // Output buffer too small - copy what fits and return error
    bcopy(msg.rcv.dataBuffer, outValues, (*actualCount) << 2);
    *actualCount = intCount;
    return -0x133;  // MIG_ARRAY_TOO_LARGE
}

// Get character array values from device parameter
int __IOGetCharValues(port_t masterPort, int objNum, unsigned int *paramName,
                      unsigned int maxCount, void *outValues, unsigned int *actualCount)
{
    kern_return_t result;
    mach_port_t replyPort;
    int i;
    unsigned int dataSize;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int inputHeader1;
            int objectNumber;
            unsigned int paramDescriptor;
            unsigned int paramNameData[16];  // 64 bytes for parameter name
            int maxCountHeader;
            unsigned int maxCountValue;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int dataDescriptor;
            unsigned char dataBuffer[512];
        } rcv;
    } msg;

    // Initialize send message
    msg.send.inputHeader1 = 0x10012002;
    msg.send.objectNumber = objNum;
    msg.send.paramDescriptor = 0x10400808;

    // Copy parameter name (16 dwords = 64 bytes)
    for (i = 0; i < 16; i++) {
        msg.send.paramNameData[i] = paramName[i];
    }

    msg.send.maxCountHeader = 0x10012002;
    msg.send.maxCountValue = maxCount;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x6c;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaa1;  // 2721

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x224, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb05) {  // 2821
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize - 0x24 >= 0x201) || msg.rcv.msgBits != 0x01) {
        if (msg.rcv.msgSize != 0x20 || msg.rcv.msgBits != 0x01 || msg.rcv.returnCode == 0) {
            return -300;
        }
    }

    if (msg.rcv.resultHeader1 != 0x10012002) {
        return -300;
    }

    // Check for error return
    if (msg.rcv.returnCode != 0) {
        return msg.rcv.returnCode;
    }

    // Validate and extract data
    if ((msg.rcv.dataDescriptor & 0x3000FFFF) != 0x10000808) {
        return -300;
    }

    // Extract data size
    dataSize = (msg.rcv.dataDescriptor >> 16) & 0xFFF;

    // Verify message size matches
    if (msg.rcv.msgSize != ((dataSize + 3) & 0xFFFFFFFC) + 0x24) {
        return -300;
    }

    // Copy output data
    if (dataSize <= *actualCount) {
        bcopy(msg.rcv.dataBuffer, outValues, dataSize);
        *actualCount = dataSize;
        return msg.rcv.returnCode;
    }

    // Output buffer too small - copy what fits and return error
    bcopy(msg.rcv.dataBuffer, outValues, *actualCount);
    *actualCount = dataSize;
    return -0x133;  // MIG_ARRAY_TOO_LARGE
}

// Power Management: Get power event
int __PMGetPowerEvent(port_t masterPort, unsigned int *eventOut)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int eventValue;
        } rcv;
    } msg;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x18;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaaf;  // 2735

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x28, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb13) {  // 2835
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize == 0x28 && msg.rcv.msgBits == 0x01) ||
        (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 && msg.rcv.returnCode != 0)) {

        if (msg.rcv.resultHeader1 != 0x10012002) {
            return -300;
        }

        // Check for error return
        if (msg.rcv.returnCode != 0) {
            return msg.rcv.returnCode;
        }

        // Extract event value
        if (msg.rcv.resultHeader2 != 0x10012002) {
            return -300;
        }
        *eventOut = msg.rcv.eventValue;

        return 0;
    }

    return -300;
}

// Power Management: Get power status
int __PMGetPowerStatus(port_t masterPort, unsigned int *statusOut)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader1;
            int resultHeader2;
            unsigned int statusValue1;
            unsigned int statusValue2;
            unsigned int statusValue3;
        } rcv;
    } msg;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x18;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xab0;  // 2736

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x30, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb14) {  // 2836
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if ((msg.rcv.msgSize == 0x30 && msg.rcv.msgBits == 0x01) ||
        (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 && msg.rcv.returnCode != 0)) {

        if (msg.rcv.resultHeader1 != 0x10012002) {
            return -300;
        }

        // Check for error return
        if (msg.rcv.returnCode != 0) {
            return msg.rcv.returnCode;
        }

        // Extract status values (3 integers)
        if (msg.rcv.resultHeader2 != 0x10032002) {
            return -300;
        }
        statusOut[0] = msg.rcv.statusValue1;
        statusOut[1] = msg.rcv.statusValue2;
        statusOut[2] = msg.rcv.statusValue3;

        return 0;
    }

    return -300;
}

// Power Management: Set power state
int __PMSetPowerState(port_t masterPort, int stateValue, unsigned int param3)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int stateDescriptor1;
            int stateValueData;
            int param3Descriptor;
            unsigned int param3Value;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Initialize send message
    msg.send.stateDescriptor1 = 0x10021001;
    msg.send.stateValueData = stateValue;
    msg.send.param3Descriptor = 0x10012002;
    msg.send.param3Value = param3;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x28;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xaae;  // 2734

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb12) {  // 2834
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Power Management: Set power management
int __PMSetPowerManagement(port_t masterPort, int managementValue, unsigned int param3)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            // Send data
            int mgmtDescriptor1;
            int mgmtValueData;
            int param3Descriptor;
            unsigned int param3Value;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Initialize send message
    msg.send.mgmtDescriptor1 = 0x10021001;
    msg.send.mgmtValueData = managementValue;
    msg.send.param3Descriptor = 0x10012002;
    msg.send.param3Value = param3;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x28;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xab1;  // 2737

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb15) {  // 2837
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Power Management: Restore defaults
int __PMRestoreDefaults(port_t masterPort)
{
    kern_return_t result;
    mach_port_t replyPort;

    // Mach message buffer
    union {
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
        } send;
        struct {
            char pad[3];
            char msgBits;
            int msgSize;
            port_t targetPort;
            port_t replyPort;
            int msgId;
            int returnCode;
            int resultHeader;
        } rcv;
    } msg;

    // Set up Mach message header
    msg.send.msgBits = 0x01;
    msg.send.msgSize = 0x18;
    msg.send.targetPort = masterPort;
    replyPort = mig_get_reply_port();
    msg.send.replyPort = replyPort;
    msg.send.msgId = 0xab2;  // 2738

    // Send message and receive reply
    result = msg_rpc(&msg.send.pad[0], 0, 0x20, 0, 0);

    if (result != KERN_SUCCESS) {
        if (result == -0xca) {  // MACH_SEND_INVALID_DEST
            mig_dealloc_reply_port(replyPort);
        }
        return result;
    }

    // Parse reply message
    if (msg.rcv.msgId != 0xb16) {  // 2838
        return -0x12d;  // MIG_REPLY_MISMATCH
    }

    // Validate reply structure
    if (msg.rcv.msgSize == 0x20 && msg.rcv.msgBits == 0x01 &&
        msg.rcv.resultHeader == 0x10012002) {

        // Return the error code (or 0 for success)
        if (msg.rcv.returnCode == 0) {
            return 0;
        }
        return msg.rcv.returnCode;
    }

    return -300;
}

// Static instance variable for singleton
static IODeviceMaster *thisTasksId = nil;

@implementation IODeviceMaster

//
// Class methods
//

+ new
{
    // Singleton pattern - return existing instance or create new one
    if (thisTasksId == nil) {
        // Allocate new instance
        thisTasksId = [super new];

        // Get the device master port
        thisTasksId->deviceMasterPort = device_master_self();
    }

    return thisTasksId;
}

//
// Instance methods
//

- free
{
    // Simple free - just return self
    // Port is managed by the system
    return self;
}

- (kern_return_t)createMachPort:(port_t *)port objectNumber:(int)objNum
{
    // Call __IOCreateMachPort with master port, object number, and port pointer
    return __IOCreateMachPort(deviceMasterPort, objNum, port);
}

//
// Parameter access methods
//

- (kern_return_t)getCharValues:(char *)values
                  forParameter:(const char *)paramName
                  objectNumber:(int)objNum
                         count:(unsigned int *)count
{
    // Call __IOGetCharValues with master port and parameters
    // Parameter name is passed as 64-byte buffer (16 dwords)
    // maxCount is passed as *count (current value)
    return __IOGetCharValues(deviceMasterPort, objNum, (unsigned int *)paramName,
                             *count, values, count);
}

- (kern_return_t)getIntValues:(unsigned int *)values
                 forParameter:(const char *)paramName
                 objectNumber:(int)objNum
                        count:(unsigned int *)count
{
    // Call __IOGetIntValues with master port and parameters
    // Parameter name is passed as 64-byte buffer (16 dwords)
    // maxCount is passed as *count (current value)
    return __IOGetIntValues(deviceMasterPort, objNum, (unsigned int *)paramName,
                            *count, values, count);
}

- (kern_return_t)setCharValues:(const char *)values
                  forParameter:(const char *)paramName
                  objectNumber:(int)objNum
                         count:(unsigned int)count
{
    // Call __IOSetCharValues with master port and parameters
    // Parameter name is passed as 64-byte buffer (16 dwords)
    return __IOSetCharValues(deviceMasterPort, objNum, (unsigned int *)paramName,
                            values, count);
}

- (kern_return_t)setIntValues:(const unsigned int *)values
                 forParameter:(const char *)paramName
                 objectNumber:(int)objNum
                        count:(unsigned int)count
{
    // Call __IOSetIntValues with master port and parameters
    // Parameter name is passed as 64-byte buffer (16 dwords)
    return __IOSetIntValues(deviceMasterPort, objNum, (unsigned int *)paramName,
                           values, count);
}

//
// Device lookup methods
//

- (kern_return_t)lookUpByDeviceName:(const char *)deviceName
                       objectNumber:(int *)objNum
                         deviceKind:(const char **)kind
{
    // Call __IOLookupByDeviceName with master port and parameters
    return __IOLookupByDeviceName(deviceMasterPort, deviceName, objNum, kind);
}

- (kern_return_t)lookUpByObjectNumber:(int)objNum
                           deviceKind:(const char **)kind
                           deviceName:(char **)name
{
    // Call __IOLookupByObjectNumber with master port and parameters
    return __IOLookupByObjectNumber(deviceMasterPort, objNum, kind, name);
}

@end
