/* Read-only tree matching shared by the independent AWACS and Screamer bundles. */
#ifndef PPC_SCREAMER_TREE_H
#define PPC_SCREAMER_TREE_H
#ifndef SCREAMER_ADAPTER_TEST
#import <driverkit/ppc/IOTreeDevice.h>
#import <machdep/ppc/DeviceTree.h>
#endif
#include "ScreamerIdentity.h"
typedef struct {
    DTEntry nodes[512];
    unsigned int parents[512],count,candidate;
} ScreamerTree;
static int screamer_tree_property(void *context,unsigned int node,
    const char *name,ScreamerBytes *bytes)
{
    ScreamerTree *tree=context;
    void *value=0;
    int length=0;
    bytes->bytes=0;bytes->length=0;
    if(!node || node>tree->count ||
        DTGetProperty(tree->nodes[node-1],name,&value,&length)!=kSuccess || length<0) return 0;
    bytes->bytes=value;bytes->length=(unsigned int)length;return 1;
}
static unsigned int screamer_tree_parent(void *context,unsigned int node)
{
    ScreamerTree *tree=context;
    return node && node<=tree->count?tree->parents[node-1]:0;
}
static int screamer_tree_description(ScreamerTree *tree,id description)
{
    DTEntry root,child,wanted=(DTEntry)[description getRef];
    DTEntryIterator iterator;
    unsigned int i,j;
    int status;
    memset(tree,0,sizeof(*tree));
    if(!wanted || DTLookupEntry(0,"/",&root)!=kSuccess) return 0;
    tree->nodes[0]=root;tree->count=1;
    for(i=0;i<tree->count;++i) {
        if(tree->nodes[i]==wanted) tree->candidate=i+1;
        if(DTCreateEntryIterator(tree->nodes[i],&iterator)!=kSuccess) return 0;
        while((status=DTIterateEntries(iterator,&child))==kSuccess) {
            if(tree->count==512) {DTDisposeEntryIterator(iterator);return 0;}
            for(j=0;j<tree->count;++j) if(tree->nodes[j]==child) break;
            if(j!=tree->count) {DTDisposeEntryIterator(iterator);return 0;}
            tree->nodes[tree->count]=child;tree->parents[tree->count++]=i+1;
        }
        DTDisposeEntryIterator(iterator);
        if(status!=kIterationDone) return 0;
    }
    return tree->candidate!=0;
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
