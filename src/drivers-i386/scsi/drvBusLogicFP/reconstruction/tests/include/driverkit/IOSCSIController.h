#ifndef BLFP_TEST_IOSCSI_CONTROLLER_H
#define BLFP_TEST_IOSCSI_CONTROLLER_H
@interface IOSCSIController
{
    char blfp_test_inherited_instance_prefix[0x244];
}
+ (id)alloc;
- (id)free;
- (void)receiveMsg;
- (const char *)name;
- (int)interruptPort;
- (id)initFromDeviceDescription:(id)description;
- (void)reserveTarget:(int)target lun:(int)lun forOwner:(id)owner;
- (void)registerDevice;
@end
#endif
