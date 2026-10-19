"""Required observable public-caller paths from review findings I1-I3."""

VERIFY=("verify-3","verify-0","verify-4","verify-5","verify-subsystem-reject","verify-product-reject")
SUBMIT=("submit-frozen-priority","submit-host-exhausted","submit-immediate")
COMPLETE=("complete-host-handoff","complete-device-redispatch","complete-finish-queue-full","complete-thaw-redispatch")
HANDLERS={"reset-precedence":"SCSIhIntSrst","ioerror-precedence":"SCSIhIntIOError","seq-length":"SCSIhCheckLength",
          "scsi-selection":"SCSIhIntSelto","scsi-busfree":"SCSIhIntFree","scsi-parity":"SCSIhParityError",
          "break":"SCSIhBreakInterrupt","seq-sentinel-a0":"SCSIhBreakInterrupt","seq-sentinel-fallback":"SCSIhAbortTarget"}
REQUIRED={"task13-fix1-"+tag:("SCSIVerifyAdapter" if tag in VERIFY else "SCSIQueueIOB" if tag in SUBMIT else "SCSIBackEndISR")
          for tag in (*VERIFY,*SUBMIT,*COMPLETE,*HANDLERS)}


def complete_cases(cases,results):
    ids=[c["id"] for c in cases];actual=[r["executed_case_id"] for r in results]
    if (len(ids)!=22 or len(set(ids))!=22 or set(ids)!=set(REQUIRED) or actual!=ids or
            any(c["entry"]!=REQUIRED[c["id"]] for c in cases)):
        raise ValueError("fix1 omitted/duplicate/wrong public caller case")


def scalar(result,region,offset,width=4):
    for key,value in result["observations"]["memory"].items():
        name,start=key.rsplit("+",1);start=int(start)
        raw=bytes.fromhex(value["bytes"] if isinstance(value,dict) else value)
        if name==region and start<=offset and offset+width<=start+len(raw):
            return int.from_bytes(raw[offset-start:offset-start+width],"big")
    raise ValueError("fix1 required caller state is not observed")


def pointer(result,region,offset):
    for key,value in result["observations"]["memory"].items():
        name,start=key.rsplit("+",1);relative=str(offset-int(start))
        if name==region and isinstance(value,dict) and relative in value["pointers"]:return value["pointers"][relative]
    raise ValueError("fix1 required declared pointer is not observed")


def effects(case,result):
    tag=case["id"].removeprefix("task13-fix1-");entry=case["entry"]
    calls=[c for c in result["api_calls"] if c["owner"]==entry];names=[c["callee"] for c in calls]
    publications=[p for p in result["publications"] if p["owner"]==entry]
    trace=result["observations"]["trace"]
    if tag in VERIFY:
        if names[:5]!=["OSMReadPCIConfigurationDword","OSMWritePCIConfigurationDword","OSMMapIOHandle","OSMReadPCIConfigurationDword","OSMReadPCIConfigurationDword"]:
            raise ValueError("I1 PCI/map/product/subsystem caller order differs")
        mapping=calls[2]
        if mapping["arguments"][1:6]!=[1 if tag=="verify-0" else 0,0,256,0,2]:raise ValueError("I1 actual map arguments differ")
        if (scalar(result,"adapter",1728)!=0 or pointer(result,"adapter",1720)!="OSMReadUExact8" or
                pointer(result,"adapter",1724)!="OSMWriteUExact8"):
            raise ValueError("I1 mapped register callback publication differs")
        if tag.endswith("reject"):
            wanted=1 if tag=="verify-subsystem-reject" else 5
            if (result["observations"]["return"]!=wanted or "SCSIRGetConfiguration" in names or
                    scalar(result,"adapter",2584)!=0xa5a5a5a5 or pointer(result,"adapter",32) is not None or
                    scalar(result,"adapter",1740)!=0x5a5a5a5a or scalar(result,"adapter",1744)!=0 or
                    {(p["offset"],p["size"]) for p in publications}!={(1720,4),(1724,4),(1728,4)}):
                raise ValueError("I1 post-map rejection partial state differs")
            if names.count("SCSIxGetNextSubSystemSubVendorID")!=(15 if wanted==1 else 0):raise ValueError("I1 actual subsystem enumeration boundary differs")
        else:
            mode=int(tag[-1]);builder={0:"OSDStandard64BuildSCB",3:"OSDSwapping32BuildSCB",4:"OSDStandardAdvBuildSCB",5:"OSDSwappingAdvBuildSCB"}[mode]
            if (result["observations"]["return"]!=0 or scalar(result,"adapter",42,1)!=mode or
                    pointer(result,"adapter",1736)!=builder or scalar(result,"adapter",2584)!=(32 if mode==3 else 64) or
                    pointer(result,"adapter",32)!="adapter+1688" or pointer(result,"adapter",1396)!="controller+0" or
                    scalar(result,"adapter",31,1)!=7 or any(scalar(result,"adapter",i,1)!=64 for i in range(1740,1756)) or
                    names[-2:]!=["SCSIxDetermineFirmwareMode","SCSIRGetConfiguration"]):
                raise ValueError("I1 firmware/SCB/LUN/configuration/count-cap publication differs")
            if ({(p["offset"],p["size"]) for p in publications if 1740<=p["offset"]<1756}!={(i,1) for i in range(1740,1756)} or
                    not any(p["offset"]==31 and p["size"]==1 for p in publications)):
                raise ValueError("I1 narrow LUN/count publication differs")
    elif tag in SUBMIT:
        wanted={"submit-frozen-priority":["SCSIrAllocateScb"],"submit-host-exhausted":["SCSIrHostQueueAppend"],"submit-immediate":["OSDBuildSCB","OSMWriteUExact8"]}[tag]
        if names!=wanted or scalar(result,"adapter",1376,1)!=1:raise ValueError("I2 normal submission allocation/disposition differs")
        if (scalar(result,"hiob",80)!=(200 if tag==SUBMIT[0] else 40) or scalar(result,"hiob",48,1)!=255 or
                any(scalar(result,"hiob",i,1) for i in (37,38,39,64,65))):
            raise ValueError("I2 public request-to-HIOB byte/priority/sense conversion differs")
        if tag==SUBMIT[0] and (scalar(result,"adapter",288)!=2 or scalar(result,"adapter",312)!=33 or scalar(result,"adapter",332)!=1):
            raise ValueError("I2 frozen-priority recovery ownership differs")
        if tag==SUBMIT[1]:
            address=0x70000000
            for m in case["memory"]:
                if m["name"]=="hiob":break
                address+=(m["size"]+4095)&~4095
            if scalar(result,"adapter",1388)!=address+32 or scalar(result,"adapter",1392)!=address+32 or trace:
                raise ValueError("I2 exhausted host queue ownership/no-delivery differs")
        else:
            if pointer(result,"active",0)!="hiob+32" or trace[-3:]!=[{"target":"registers+58","access":"write","size":1,"value":0},{"operation":"eieio"},{"operation":"sync"}]:
                raise ValueError("I2 active publication/delivery/cache/MMIO/barrier order differs")
    elif tag in COMPLETE:
        wanted={COMPLETE[0]:["SCSIrHostQueueRemove","SCSIrReturnScb","SCSIrGetScb","SCSIHQueueHIOB"],
                COMPLETE[1]:["SCSIrAllocateScb"],COMPLETE[2]:["SCSIHCheckDeviceIdle","SCSIrFinishQueueFull"],
                COMPLETE[3]:["SCSIHCheckDeviceIdle","SCSIrUnFreezeDeviceQueue","SCSIrDispatchQueuedHIOB"]}[tag]
        if names!=wanted+["SCSIxPostQueueSpecialIOB"]:raise ValueError("I2 completion handoff/thaw/callback order differs")
        if (scalar(result,"active",4)!=0xffffffff or scalar(result,"adapter",1372,1)!=1 or scalar(result,"adapter",1373,1)!=1 or
                pointer(result,"done",0)!="complete+0" or scalar(result,"completed-iob",44)!=1 or
                scalar(result,"adapter",1376,1)!={COMPLETE[0]:1,COMPLETE[1]:2,COMPLETE[2]:3,COMPLETE[3]:2}[tag] or
                scalar(result,"adapter",288)!=(2 if tag==COMPLETE[1] else 1) or scalar(result,"adapter",312) or scalar(result,"adapter",336)):
            raise ValueError("I2 completion free/active/device/done ownership differs")
        if tag==COMPLETE[2]:
            if scalar(result,"adapter",284)!=2 or scalar(result,"active",0)!=0xffffffff or trace!=[{"operation":"sync"}]:
                raise ValueError("I2 FinishQueueFull saved-limit/no-delivery differs")
        elif pointer(result,"active",0)!="hiob+0" or trace[-1]!={"operation":"sync"}:raise ValueError("I2 queued handoff/ordered completion barrier differs")
        if tag==COMPLETE[3] and scalar(result,"adapter",332):raise ValueError("I2 recovery-count thaw differs")
    elif tag in HANDLERS:
        selected=[n for n in names if n in HANDLERS.values()]
        if selected!=[HANDLERS[tag]] or names.count("SCSIhReadINTSTAT")!=2 or scalar(result,"adapter",244,1):
            raise ValueError("I3 actual handler precedence/caller loop differs")
        handler=next(c for c in calls if c["callee"]==HANDLERS[tag])
        if "sentinel" in tag or tag=="scsi-busfree":
            if handler["arguments"][1]!=0xffffffff:raise ValueError("I3 SCB-sentinel handler argument differs")
        if tag not in ("reset-precedence","ioerror-precedence"):
            restore=next(c for c in calls if c["callee"]=="SCSIhWriteHCNTRL")
            if restore["arguments"][1]!=2 or names.index(HANDLERS[tag])>=names.index("SCSIhWriteHCNTRL") or names[-1] not in ("SCSIhReadINTSTAT","SCSIxPostQueueSpecialIOB"):
                raise ValueError("I3 clear/saved-HCNTRL/return-to-poll order differs")
            if sum(o["count"] for o in result["mmio_operations"] if o["owner"]==entry and o["offset"]==146 and o["direction"]=="write")!=1:
                raise ValueError("I3 caller interrupt-clear publication differs")
        if tag=="scsi-selection" and (names[-1]!="SCSIxPostQueueSpecialIOB" or names.count("SCSIxPostQueueSpecialIOB")!=1 or scalar(result,"completed-iob",44)!=32 or scalar(result,"adapter",1372,2)!=0x0101):
            raise ValueError("I3 post-handler single completion drain differs")
    else:raise ValueError("unreviewed fix1 case identity")


def require_paths(finding, cases, results):
    entries={c["id"]:c["entry"] for c in cases}
    roots=[(entries[r["executed_case_id"]],r) for r in results]
    calls={(entry,c["callee"]) for entry,r in roots for c in r["api_calls"] if c["owner"]==entry}
    if finding=="I1":
        wanted={("SCSIVerifyAdapter",n) for n in ("SCSIxDetermineFirmwareMode","SCSIRGetConfiguration")}
        if not wanted<=calls or not any(entry=="SCSIVerifyAdapter" and r["publications"] and r["observations"].get("return")==0 for entry,r in roots):
            raise ValueError("I1 missing successful VerifyAdapter caller publications/configuration")
    elif finding=="I2":
        wanted={("SCSIQueueIOB",n) for n in ("SCSIrHostQueueAppend","SCSIrAllocateScb","OSDBuildSCB")}
        wanted|={("SCSIBackEndISR",n) for n in ("SCSIrFinishQueueFull","SCSIrUnFreezeDeviceQueue","SCSIrDispatchQueuedHIOB","SCSIrAllocateScb","SCSIHQueueHIOB")}
        if not wanted<=calls:raise ValueError("I2 missing normal submission/completion ownership: "+str(sorted(wanted-calls)))
    elif finding=="I3":
        wanted={("SCSIBackEndISR",n) for n in ("SCSIhIntSrst","SCSIhIntIOError","SCSIhCheckLength","SCSIhAbortTarget","SCSIhIntSelto","SCSIhIntFree","SCSIhParityError","SCSIhBreakInterrupt")}
        if not wanted<=calls:raise ValueError("I3 missing active BackEndISR real handler dispositions: "+str(sorted(wanted-calls)))
    else:raise ValueError("unknown Task13 review finding")
