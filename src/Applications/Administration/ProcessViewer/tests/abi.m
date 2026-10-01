#import <Foundation/Foundation.h>
#import <objc/objc-class.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import "Process.h"
#import "ProcessType.h"
#import "ProcessTableView.h"
#import "ProcessControl.h"
#import "Inspector.h"

static void check_size(const char *name, Class cls, int expected)
{
    if (cls == Nil || cls->instance_size != expected) {
        fprintf(stderr, "%s size: expected %d, got %ld\n", name, expected,
                cls == Nil ? -1L : cls->instance_size);
        exit(1);
    }
}

static void check_ivar(Class cls, const char *name, int offset, const char *encoding)
{
    Ivar ivar = class_getInstanceVariable(cls, name);
    if (ivar == NULL || ivar->ivar_offset != offset ||
        strcmp(ivar->ivar_type, encoding) != 0) {
        fprintf(stderr, "%s.%s did not match offset %d and encoding %s\n",
                cls->name, name, offset, encoding);
        exit(1);
    }
}

int main(void)
{
    Class cls;

    check_size("Process", [Process class], 32);
    cls = [Process class];
    check_ivar(cls, "_pid", 4, "i");
    check_ivar(cls, "_ppid", 8, "i");
    check_ivar(cls, "_pgid", 12, "i");
    check_ivar(cls, "_saved_euid", 16, "I");
    check_ivar(cls, "_real_uid", 20, "I");
    check_ivar(cls, "_args", 24, "@\"NSArray\"");
    check_ivar(cls, "_values", 28, "@\"NSMutableDictionary\"");

    check_size("MapTableEnumerator", [MapTableEnumerator class], 16);
    check_ivar([MapTableEnumerator class], "_mapEnum", 4,
               "{?=\"_pi\"I\"_nk\"^v\"_bs\"^v}");
    check_size("ProcessType", [ProcessType class], 16);
    check_ivar([ProcessType class], "_name", 4, "@\"NSString\"");
    check_ivar([ProcessType class], "_key", 8, "@\"NSString\"");
    check_ivar([ProcessType class], "_values", 12, "@\"NSSet\"");

    check_size("ProcessControl", [ProcessControl class], 68);
    check_ivar([ProcessControl class], "processTable", 8, "@\"ProcessTableView\"");
    check_ivar([ProcessControl class], "processTypes", 64, "@\"NSArray\"");
    check_size("ProcessTableView", [ProcessTableView class], 232);
    check_ivar([ProcessTableView class], "_highlightedColumnIdentifier", 228, "@");
    check_size("ProcessTableHeaderView", [ProcessTableHeaderView class], 116);

    check_size("Inspector", [Inspector class], 92);
    check_ivar([Inspector class], "_process", 4, "@\"Process\"");
    check_ivar([Inspector class], "_isVisible", 80, "c");
    check_ivar([Inspector class], "_minTabContainerHeight", 84, "f");
    check_ivar([Inspector class], "_minMainContainerHeight", 88, "f");

    if (sizeof(ProcessSortContext) != 8 ||
        offsetof(ProcessSortContext, ascending) != 5) {
        fprintf(stderr, "ProcessSortContext layout is not the recovered 32-bit layout\n");
        return 1;
    }
    puts("Recovered Objective-C layouts match the 32-bit reference ABI.");
    return 0;
}
