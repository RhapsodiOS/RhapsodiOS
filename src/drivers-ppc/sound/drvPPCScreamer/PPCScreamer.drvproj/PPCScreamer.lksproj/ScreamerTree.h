/* Read-only tree matching shared by the independent AWACS and Screamer bundles. */
#ifndef PPC_SCREAMER_TREE_H
#define PPC_SCREAMER_TREE_H
#ifndef SCREAMER_ADAPTER_TEST
#import <driverkit/ppc/IOTreeDevice.h>
#import <driverkit/ppc/IOPropertyTable.h>
#endif
#include "ScreamerIdentity.h"
@interface IOTreeDevice (ScreamerIteration)
+ findForIndex:(UInt32)index;
@end
typedef struct { id nodes[512]; unsigned int count,candidate; } ScreamerTree;
static int screamer_tree_property(void *context,unsigned int node,
    const char *name,ScreamerBytes *bytes)
{
    ScreamerTree *tree=context;
    void *value=0;
    ByteCount length=0;
    bytes->bytes=0;bytes->length=0;
    if(!node || node>tree->count) return 0;
    if([[tree->nodes[node-1] propertyTable] getProperty:name flags:0 value:&value
        length:&length]!=IO_R_SUCCESS) return 0;
    bytes->bytes=value;bytes->length=length;return 1;
}
static unsigned int screamer_tree_parent(void *context,unsigned int node)
{
    ScreamerTree *tree=context;
    id parent;
    unsigned int i;
    if(!node || node>tree->count) return 0;
    parent=[tree->nodes[node-1] parent];
    for(i=0;i<tree->count;++i) if(tree->nodes[i]==parent) return i+1;
    return 0;
}
static int screamer_tree_description(ScreamerTree *tree,id description)
{
    char wanted[256],path[256];
    id node;
    unsigned int i;
    memset(tree,0,sizeof(*tree));
    if([description getDevicePath:wanted maxLength:sizeof(wanted) useAlias:NO]==nil)
        return 0;
    for(i=0;i<512;++i) {
        node=[IOTreeDevice findForIndex:i];
        if(node==nil) break;
        tree->nodes[i]=node;++tree->count;
        if([node getDevicePath:path maxLength:sizeof(path) useAlias:NO]!=nil &&
            strcmp(path,wanted)==0) {
            if(tree->candidate) return 0;
            tree->candidate=i+1;
        }
    }
    return i<512 && tree->candidate!=0;
}
static ScreamerIdentity screamer_tree_identity(ScreamerTree *tree)
{
    ScreamerBytes m,c;
    ScreamerIdentity identity,result=kScreamerIdentityUnknown;
    unsigned int i,found=0;
    for(i=1;i<=tree->count;++i) {
        if(i!=tree->candidate && screamer_tree_parent(tree,i)!=tree->candidate) continue;
        screamer_tree_property(tree,i,"model",&m);
        screamer_tree_property(tree,i,"compatible",&c);
        identity=ScreamerClassify(m,c);
        if(identity==kScreamerIdentityConflict) return identity;
        if(identity==kScreamerIdentityUnknown) continue;
        if(result!=kScreamerIdentityUnknown && result!=identity) return kScreamerIdentityConflict;
        result=identity;
        if(identity==kScreamerIdentityScreamer && ++found>1) return kScreamerIdentityConflict;
    }
    return result;
}
#endif
