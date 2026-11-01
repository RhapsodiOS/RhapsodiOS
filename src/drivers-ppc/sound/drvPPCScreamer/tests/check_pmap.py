"""Exercise the actual PPC pmap provider with PTE/TLB/cache operations instrumented."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

source = Path(__file__).resolve().parents[4] / 'kernel-7/machdep/ppc/pmap.c'
text = source.read_text()
def function(name):
    match = re.search(r'\n(?:void|boolean_t)\s*\n' + name + r'\([^\{]+\{', text)
    if not match:
        return ''
    start, end, depth = match.start(), match.end(), 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

stub = r'''
#include <assert.h>
#include <stdio.h>
typedef unsigned long vm_offset_t;
typedef int vm_prot_t,boolean_t,spl_t,cache_spec_t;
struct pmap {int space;};
typedef struct pmap *pmap_t;
typedef void *queue_entry_t;
struct pte {struct {struct {int valid;} bits;} pte0;
    struct {struct {int wimg;} bits;} pte1;};
struct mapping {struct {void *next;} phys_link;
    struct {struct {int wired;} bits;} vm_info;struct pte *pte;};
struct phys_entry {struct {void *next;} phys_link;
    struct {struct {int wimg;} bits;} pte1;};
static struct pmap kernel;
static pmap_t kernel_pmap=&kernel;
static struct pte pte;
static struct mapping mapping;
static struct phys_entry physical;
static int flushes,invalidates,tlbs,raised;
#define PMAP_NULL ((pmap_t)0)
#define PHYS_NULL ((struct phys_entry *)0)
#define MAPPING_NULL ((struct mapping *)0)
#define TRUE 1
#define FALSE 0
#define PAGE_SIZE 4096
#define PTE_WIMG_DEFAULT 2
#define PTE_WIMG_IO 7
#define cache_default 0
#define cache_writethrough 1
#define cache_disable 2
#define queue_first(q) ((q)->next)
#define queue_next(q) ((q)->next)
static spl_t splhigh(void) {raised=1;return 0;}
static void splx(spl_t s) {(void)s;raised=0;}
static void sync(void) {}
static void eieio(void) {}
static void tlbsync(void) {}
static void tlbie(vm_offset_t v) {(void)v;assert(raised && !pte.pte0.bits.valid);++tlbs;}
static void flush_cache_v(vm_offset_t v,unsigned int n)
{(void)v;assert(n==4096 && raised && pte.pte0.bits.valid);++flushes;}
static void invalidate_cache_v(vm_offset_t v,unsigned int n)
{(void)v;assert(n==4096 && flushes && raised && pte.pte0.bits.valid);++invalidates;}
static vm_offset_t pmap_extract(pmap_t p,vm_offset_t v) {(void)p;(void)v;return 0x10000;}
static struct mapping *pmap_find_mapping(int space,vm_offset_t v)
{(void)space;(void)v;return &mapping;}
static struct phys_entry *pmap_find_physentry(vm_offset_t v) {(void)v;return &physical;}
static void pmap_enter(pmap_t p,vm_offset_t v,vm_offset_t pa,vm_prot_t pr,boolean_t w)
{(void)p;(void)v;(void)pa;(void)pr;mapping.vm_info.bits.wired=w;}
'''
main = r'''
int main(void) {
 pte.pte0.bits.valid=1;pte.pte1.bits.wimg=physical.pte1.bits.wimg=2;
 mapping.pte=&pte;physical.phys_link.next=&mapping;
 mapping.phys_link.next=&physical.phys_link;
 pmap_enter_cache_spec(kernel_pmap,0x20000,0x10000,3,TRUE,cache_disable);
 assert(pte.pte1.bits.wimg==7 && physical.pte1.bits.wimg==7);
 assert(flushes==1 && invalidates==1 && tlbs==1 && !raised && pte.pte0.bits.valid);
 pmap_enter_cache_spec(kernel_pmap,0x20000,0x10000,3,TRUE,cache_default);
 assert(pte.pte1.bits.wimg==2 && physical.pte1.bits.wimg==2);
 mapping.vm_info.bits.wired=0;
 assert(!pmap_set_cache_spec(kernel_pmap,0x20000,cache_disable));
 assert(!pmap_set_cache_spec(kernel_pmap,0x20001,cache_disable));
 assert(!pmap_set_cache_spec(PMAP_NULL,0x20000,cache_disable));
 mapping.vm_info.bits.wired=1;
 mapping.phys_link.next=&mapping; /* A second alias must be rejected. */
 pmap_enter_cache_spec(kernel_pmap,0x20000,0x10000,3,TRUE,cache_disable);
 assert(pte.pte1.bits.wimg==2 && !raised);
 puts("PPC pmap: cache transition, TLB ordering, restoration and alias rejection passed");
 return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    src, exe = Path(tmp)/'provider.c', Path(tmp)/'provider'
    src.write_text(stub + function('pmap_set_cache_spec') + function('pmap_enter_cache_spec') + main)
    subprocess.run([os.environ.get('CC','cc'), '-std=c89', str(src), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
