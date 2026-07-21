// Deterministic Ghidra 12.1 headless exporter and raw-layout pre-script.
// @category BinRecon

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.decompiler.DecompiledFunction;
import ghidra.app.script.GhidraScript;
import ghidra.framework.Application;
import ghidra.program.database.mem.FileBytes;
import ghidra.program.model.address.*;
import ghidra.program.model.block.*;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.lang.Language;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.pcode.HighFunction;
import ghidra.program.model.pcode.PcodeOp;
import ghidra.program.model.reloc.Relocation;
import ghidra.program.model.symbol.*;
import ghidra.util.exception.CancelledException;

public final class ExportAnalysis extends GhidraScript {
    private static final String LANGUAGE = "x86:LE:32:default";
    private static final int MAX_DECOMPILED_C = 1024 * 1024;
    private static final int MAX_DECOMPILE_MESSAGE = 16 * 1024;
    private final NavigableMap<Long,List<Long>> relocationIndexesByAddress=new TreeMap<>();

    @Override
    protected void run() throws Exception {
        Args args = Args.parse(getScriptArgs());
        verifyExternalInput(args);
        if ("prepare".equals(args.mode)) {
            prepare(args);
            return;
        }
        if (!"export".equals(args.mode)) {
            throw new IllegalArgumentException("mode must be prepare or export");
        }
        export(args);
    }

    private void verifyExternalInput(Args args) throws Exception {
        Path input = Paths.get(args.required("--input")).toRealPath();
        long expectedSize = Long.parseLong(args.required("--size"));
        String expectedHash = args.required("--sha256").toUpperCase(Locale.ROOT);
        if (!Files.isRegularFile(input) || Files.size(input) != expectedSize) {
            throw new IOException("input size or type changed");
        }
        if (!sha256(input).equals(expectedHash)) {
            throw new IOException("input SHA-256 changed");
        }
        if (!LANGUAGE.equals(args.required("--language"))) {
            throw new IOException("unexpected requested language");
        }
    }

    private void verifyLanguage() throws IOException {
        Language language = currentProgram.getLanguage();
        String id = language.getLanguageID().toString();
        if (!LANGUAGE.equals(id) || language.getDefaultSpace().getSize() != 32 ||
                language.isBigEndian()) {
            throw new IOException("program is not x86:LE:32:default");
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String,Object> readLayout(Args args) throws Exception {
        Object parsed = new JsonParser(Files.readString(
            Paths.get(args.required("--layout")), StandardCharsets.UTF_8)).parse();
        if (!(parsed instanceof Map)) throw new IOException("layout root is not an object");
        Map<String,Object> layout = (Map<String,Object>)parsed;
        if (!"ghidra-layout-v1".equals(layout.get("schema_version")) ||
                !LANGUAGE.equals(layout.get("language"))) {
            throw new IOException("layout contract mismatch");
        }
        Map<String,Object> identity = object(layout.get("input"), "input");
        if (!args.required("--sha256").equalsIgnoreCase(string(identity.get("sha256"))) ||
                Long.parseLong(args.required("--size")) != number(identity.get("size"))) {
            throw new IOException("layout identity mismatch");
        }
        return layout;
    }

    private void prepare(Args args) throws Exception {
        verifyLanguage();
        Map<String,Object> layout = readLayout(args);

        Memory memory = currentProgram.getMemory();
        for (MemoryBlock block : memory.getBlocks()) memory.removeBlock(block, monitor);
        AddressSpace space = currentProgram.getAddressFactory().getDefaultAddressSpace();
        currentProgram.setImageBase(space.getAddress(number(layout.get("image_base"))), true);
        Path inputPath = Paths.get(args.required("--input"));
        FileBytes fileBytes;
        try (InputStream stream = Files.newInputStream(inputPath)) {
            fileBytes = memory.createFileBytes(inputPath.getFileName().toString(), 0,
                Files.size(inputPath), stream, monitor);
        }
        for (Object item : array(layout.get("sections"), "sections")) {
            Map<String,Object> section = object(item, "section");
            String name = blockName(section);
            long address = number(section.get("address"));
            long offset = number(section.get("offset"));
            long size = number(section.get("size"));
            boolean initialized = Boolean.TRUE.equals(section.get("initialized"));
            if (size == 0) continue;
            MemoryBlock block;
            if (initialized) {
                if (offset < 0 || size > Files.size(inputPath) - offset)
                    throw new IOException("initialized section is outside input");
                block = memory.createInitializedBlock(name, space.getAddress(address),
                    fileBytes, offset, size, false);
            } else {
                block = memory.createUninitializedBlock(name, space.getAddress(address), size, false);
            }
            String permissions = string(section.get("permissions"));
            block.setRead(permissions.contains("r"));
            block.setWrite(permissions.contains("w"));
            block.setExecute(permissions.contains("x"));
        }
        SymbolTable symbols = currentProgram.getSymbolTable();
        for (Object item : array(layout.get("symbols"), "symbols")) {
            Map<String,Object> symbol = object(item, "symbol");
            if ("external".equals(string(symbol.get("binding"))) && symbol.get("section") == null) {
                currentProgram.getExternalManager().addExtLocation(
                    "UNKNOWN", string(symbol.get("name")), null, SourceType.IMPORTED);
                continue;
            }
            SourceType source = "local".equals(string(symbol.get("binding")))
                ? SourceType.ANALYSIS : SourceType.IMPORTED;
            symbols.createLabel(space.getAddress(number(symbol.get("address"))),
                string(symbol.get("name")), source);
        }
        installRelocations(layout, space);
        realizeEntryPoints(layout, space);
        linkRelocations(layout, space);
    }

    private String blockName(Map<String,Object> section) {
        return "section-"+number(section.get("ordinal"));
    }

    private void installRelocations(Map<String,Object> layout, AddressSpace space) throws Exception {
        Memory memory=currentProgram.getMemory();
        Map<Long,Address> sections=new HashMap<>();
        for(Object value:array(layout.get("sections"),"sections")){Map<String,Object> section=object(value,"section");
            sections.put(number(section.get("ordinal")),space.getAddress(number(section.get("address"))));}
        Map<String,Map<String,Object>> symbolLayouts=new HashMap<>();
        for(Object value:array(layout.get("symbols"),"symbols")){Map<String,Object> symbol=object(value,"symbol");symbolLayouts.put(string(symbol.get("name")),symbol);}
        for(Object value:array(layout.get("relocations"),"relocations")){Map<String,Object> relocation=object(value,"relocation");
            Address place=space.getAddress(number(relocation.get("address"))); int type=(int)number(relocation.get("type"));
            int width=(int)number(relocation.get("width")); long addend=number(relocation.get("addend"));
            String targetName=relocation.get("target")==null?null:string(relocation.get("target")); Address target=null;
            if(relocation.get("target_section_ordinal")!=null){target=sections.get(number(relocation.get("target_section_ordinal")));}
            else if(targetName!=null){Map<String,Object> symbol=symbolLayouts.get(targetName);if(symbol!=null&&symbol.get("section")!=null){
                    target=space.getAddress(number(symbol.get("address")));
                }else{for(Object sectionValue:array(layout.get("sections"),"sections")){Map<String,Object> section=object(sectionValue,"section");
                    if(targetName.equals(section.get("name"))){target=sections.get(number(section.get("ordinal")));break;}}}}
            Relocation.Status status; Long applied=null;
            if(type!=0){status=Relocation.Status.UNSUPPORTED;}
            else if(target==null){status=Relocation.Status.SKIPPED;}
            else {long placeValue=place.getOffset(), targetValue=target.getOffset();
                long computed=Boolean.TRUE.equals(relocation.get("pc_relative"))?targetValue+addend-placeValue:targetValue+addend;
                if(!fitsRelocation(computed,width,Boolean.TRUE.equals(relocation.get("pc_relative")))) status=Relocation.Status.FAILURE;
                else {byte[] bytes=littleEndian(computed,width);memory.setBytes(place,bytes);status=Relocation.Status.APPLIED;applied=computed;}}
            long[] values=applied==null?new long[]{addend}:new long[]{applied,target.getOffset(),addend};
            currentProgram.getRelocationTable().add(place,status,type,values,
                unhex(string(relocation.get("original_bytes"))),targetName);
        }
    }

    private void realizeEntryPoints(Map<String,Object> layout,AddressSpace space) throws Exception {
        Memory memory=currentProgram.getMemory();FunctionManager functions=currentProgram.getFunctionManager();SymbolTable symbols=currentProgram.getSymbolTable();
        for(Object value:array(layout.get("entry_points"),"entry points")){Map<String,Object> entry=object(value,"entry point");
            Address address=space.getAddress(number(entry.get("address")));MemoryBlock block=memory.getBlock(address);
            if(block==null||!block.isExecute())throw new IOException("entry point is unmapped or non-executable: "+address);
            if(!disassemble(address)||currentProgram.getListing().getInstructionAt(address)==null)throw new IOException("entry point disassembly failed: "+address);
            Function function=functions.getFunctionAt(address);if(function==null)function=createFunction(address,string(entry.get("name")));
            if(function==null||!function.getEntryPoint().equals(address))throw new IOException("entry point function creation failed: "+address);
            symbols.addExternalEntryPoint(address);}
    }

    private void linkRelocations(Map<String,Object> layout,AddressSpace space) throws Exception {
        ReferenceManager references=currentProgram.getReferenceManager();SymbolTable symbols=currentProgram.getSymbolTable();
        Map<Long,Address> sections=new HashMap<>();for(Object value:array(layout.get("sections"),"sections")){Map<String,Object> section=object(value,"section");sections.put(number(section.get("ordinal")),space.getAddress(number(section.get("address"))));}
        Map<String,Map<String,Object>> symbolLayouts=new HashMap<>();for(Object value:array(layout.get("symbols"),"symbols")){Map<String,Object> symbol=object(value,"symbol");symbolLayouts.put(string(symbol.get("name")),symbol);}
        for(Object value:array(layout.get("relocations"),"relocations")){Map<String,Object> relocation=object(value,"relocation");Address field=space.getAddress(number(relocation.get("address")));
            Instruction owner=currentProgram.getListing().getInstructionContaining(field);Address source=owner==null?field:owner.getAddress();String targetName=relocation.get("target")==null?null:string(relocation.get("target"));
            Address target=null;if(relocation.get("target_section_ordinal")!=null)target=sections.get(number(relocation.get("target_section_ordinal")));
            else if(targetName!=null){Map<String,Object> symbol=symbolLayouts.get(targetName);if(symbol!=null&&symbol.get("section")!=null)target=space.getAddress(number(symbol.get("address")));}
            RefType refType=owner!=null&&(owner.getFlowType().isCall()||owner.getFlowType().isJump())?owner.getFlowType():RefType.DATA;
            if(target!=null){Reference reference=references.getReference(source,target,0);if(reference==null)reference=references.addMemoryReference(source,target,refType,SourceType.IMPORTED,0);
                Symbol targetSymbol=symbols.getPrimarySymbol(target);if(targetSymbol!=null)references.setAssociation(targetSymbol,reference);}
            else if(targetName!=null){ExternalLocation location=currentProgram.getExternalManager().getUniqueExternalLocation("UNKNOWN",targetName);
                if(location==null)throw new IOException("external relocation target is missing: "+targetName);
                boolean exists=false;for(Reference reference:references.getReferencesFrom(source))if(reference instanceof ExternalReference&&targetName.equals(((ExternalReference)reference).getLabel()))exists=true;
                if(!exists)references.addExternalReference(source,0,location,SourceType.IMPORTED,refType);}}
    }

    private static boolean fitsRelocation(long value,int width,boolean signed){if(width!=1&&width!=2&&width!=4)return false;
        int bits=width*8;if(signed){long min=-(1L<<(bits-1)),max=(1L<<(bits-1))-1;return value>=min&&value<=max;}
        long max=(1L<<bits)-1;return value>=0&&value<=max;}
    private static byte[] littleEndian(long value,int width){byte[] out=new byte[width];for(int i=0;i<width;i++)out[i]=(byte)(value>>>(i*8));return out;}
    private static byte[] unhex(String value){if((value.length()&1)!=0)throw new IllegalArgumentException("odd hex length");byte[] out=new byte[value.length()/2];
        for(int i=0;i<out.length;i++){int high=Character.digit(value.charAt(i*2),16),low=Character.digit(value.charAt(i*2+1),16);if(high<0||low<0)throw new IllegalArgumentException("invalid hex");out[i]=(byte)((high<<4)|low);}return out;}

    private void export(Args args) throws Exception {
        verifyLanguage();
        if (currentProgram.getMemory().getBlocks().length == 0)
            throw new IOException("program has no memory layout");
        String executablePath = currentProgram.getExecutablePath();
        if (executablePath == null || !Files.isSameFile(programExecutablePath(executablePath),
                Paths.get(args.required("--input")))) {
            throw new IOException("program executable identity does not match input");
        }
        Map<String,Object> layout = args.values.containsKey("--layout") ? readLayout(args) : null;
        if (layout != null) verifyPreparedLayout(layout);
        if (layout != null) linkRelocations(layout,
            currentProgram.getAddressFactory().getDefaultAddressSpace());
        Map<String,Object> root = new LinkedHashMap<>();
        ReferenceManager referenceManager = currentProgram.getReferenceManager();
        if (referenceManager == null) throw new IOException("reference manager unavailable");
        root.put("schema_version", "analysis-v1");
        Map<String,Object> input = map();
        input.put("path", Paths.get(args.required("--input")).toRealPath().toString());
        input.put("size", Long.parseLong(args.required("--size")));
        input.put("sha256", args.required("--sha256").toUpperCase(Locale.ROOT));
        input.put("architecture", "i386"); input.put("endianness", "little");
        root.put("input", input);
        Map<String,Object> analyzer = map();
        analyzer.put("name", "Ghidra");
        analyzer.put("version", analyzerVersion());
        analyzer.put("invocation", "analyzeHeadless ExportAnalysis.java");
        root.put("analyzer", analyzer);

        List<Object> fallbackBacking=new ArrayList<>();
        root.put("sections", exportSections(layout,fallbackBacking));
        root.put("symbols", exportSymbols(layout));
        root.put("relocations", exportRelocations(layout));
        List<Object> imports = new ArrayList<>(), strings = new ArrayList<>(),
                     summaries = new ArrayList<>();
        ReferenceExport referenceExport = exportAllReferences(referenceManager);
        root.put("functions", exportFunctions(summaries));
        root.put("references", referenceExport.normalized);
        root.put("imports", exportImports(imports));
        root.put("strings", exportStrings(strings));
        Map<String,Object> extensions = map(), ghidra = map();
        ghidra.put("language", currentProgram.getLanguage().getLanguageID().toString());
        ghidra.put("image_base", currentProgram.getImageBase().getOffset());
        ghidra.put("decompiler_pcode", summaries);
        ghidra.put("reference_metadata", referenceExport.metadata);
        ghidra.put("instruction_reference_indexes",
            referenceExport.instructionIndexes(currentProgram));
        if (layout != null) {
            ghidra.put("fallback_sections", array(layout.get("sections"), "sections"));
            ghidra.put("fallback_symbols", array(layout.get("symbols"), "symbols"));
            ghidra.put("fallback_relocations", array(layout.get("relocations"), "relocations"));
            ghidra.put("fallback_backing", fallbackBacking);
            ghidra.put("fallback_relocation_status", exportFallbackRelocationStatus(layout));
        }
        extensions.put("ghidra", ghidra); root.put("extensions", extensions);
        writeAtomically(Paths.get(args.required("--output")), root);
    }

    private void verifyPreparedLayout(Map<String,Object> layout) throws Exception {
        if (!LANGUAGE.equals(layout.get("language")) ||
                currentProgram.getImageBase().getOffset() != number(layout.get("image_base")))
            throw new IOException("prepared image base/language mismatch");
        List<Object> expected = array(layout.get("sections"), "sections");
        List<MemoryBlock> actual = new ArrayList<>(Arrays.asList(currentProgram.getMemory().getBlocks()));
        Collections.sort(actual, Comparator.comparingLong(b -> b.getStart().getOffset()));
        if (actual.size() != expected.stream().filter(x -> number(object(x,"section").get("size")) != 0).count())
            throw new IOException("prepared memory block count mismatch");
        int index = 0;
        for (Object value : expected) {
            Map<String,Object> section = object(value, "section");
            if (number(section.get("size")) == 0) continue;
            MemoryBlock block = actual.get(index++);
            String permissions = string(section.get("permissions"));
            if (!block.getName().equals(blockName(section)) ||
                    block.getStart().getOffset() != number(section.get("address")) ||
                    block.getSize() != number(section.get("size")) ||
                    block.isInitialized() != Boolean.TRUE.equals(section.get("initialized")) ||
                    block.isRead() != permissions.contains("r") ||
                    block.isWrite() != permissions.contains("w") ||
                    block.isExecute() != permissions.contains("x"))
                throw new IOException("prepared memory layout mismatch");
        }
        List<Object> relocations=array(layout.get("relocations"),"relocations");
        if(currentProgram.getRelocationTable().getSize()!=relocations.size())
            throw new IOException("prepared relocation count mismatch");
        for(Object value:relocations){Map<String,Object> expectedRelocation=object(value,"relocation");
            Address address=currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(number(expectedRelocation.get("address")));
            List<Relocation> actualRelocations=currentProgram.getRelocationTable().getRelocations(address);
            boolean matched=false;for(Relocation relocation:actualRelocations)if(relocation.getType()==number(expectedRelocation.get("type"))&&
                Objects.equals(relocation.getSymbolName(),expectedRelocation.get("target"))&&relocation.getLength()==number(expectedRelocation.get("width"))&&
                Arrays.equals(relocation.getBytes(),unhex(string(expectedRelocation.get("original_bytes")))))matched=true;
            if(!matched)throw new IOException("prepared relocation table mismatch");}
    }

    private String analyzerVersion() throws IOException {
        String version = Application.getApplicationVersion();
        if (!version.matches("12\\.1(?:\\..*)?"))
            throw new IOException("Ghidra 12.1 release line is required");
        return "12.1";
    }

    private Path programExecutablePath(String value) {
        if (File.separatorChar == '\\' && value.matches("^/[A-Za-z]:/.*")) value=value.substring(1);
        return Paths.get(value);
    }

    private List<Object> exportSections(Map<String,Object> layout,List<Object> fallbackBacking) throws Exception {
        if(layout!=null){List<Object> out=new ArrayList<>();for(Object value:array(layout.get("sections"),"sections")){
            Map<String,Object> section=object(value,"section"),item=map(),backing=map();long size=number(section.get("size"));
            MemoryBlock block=size==0?null:currentProgram.getMemory().getBlock(blockName(section));
            item.put("name",section.get("name"));item.put("address",section.get("address"));item.put("offset",section.get("offset"));
            item.put("size",section.get("size"));item.put("permissions",section.get("permissions"));item.put("sha256",blockHash(block,size));out.add(item);
            backing.put("ordinal",section.get("ordinal"));backing.put("initialized",section.get("initialized"));
            backing.put("source_offset",block==null||!Boolean.TRUE.equals(section.get("initialized"))?null:sourceOffset(block));fallbackBacking.add(backing);}
            return out;}
        List<MemoryBlock> blocks = new ArrayList<>(Arrays.asList(currentProgram.getMemory().getBlocks()));
        Collections.sort(blocks, Comparator.comparingLong((MemoryBlock b) -> b.getStart().getOffset())
            .thenComparing(MemoryBlock::getName));
        List<Object> out = new ArrayList<>();
        for (MemoryBlock block : blocks) {
            monitor.checkCancelled();
            Map<String,Object> item = map();
            item.put("name", block.getName()); item.put("address", block.getStart().getOffset());
            item.put("offset", sourceOffset(block)); item.put("size", block.getSize());
            item.put("permissions", (block.isRead()?"r":"")+(block.isWrite()?"w":"")+(block.isExecute()?"x":""));
            item.put("sha256", blockHash(block,block.getSize())); out.add(item);
        }
        return out;
    }

    private String blockHash(MemoryBlock block,long size) throws Exception {MessageDigest digest=MessageDigest.getInstance("SHA-256");
        byte[] buffer=new byte[1024*1024];long done=0;while(done<size){int count=(int)Math.min(buffer.length,size-done);Address at=block.getStart().add(done);
            if(block.isInitialized())currentProgram.getMemory().getBytes(at,buffer,0,count);else Arrays.fill(buffer,0,count,(byte)0);digest.update(buffer,0,count);done+=count;}
        return hex(digest.digest());}

    private long sourceOffset(MemoryBlock block) {
        List<MemoryBlockSourceInfo> infos = block.getSourceInfos();
        if (infos.isEmpty()) return 0;
        long offset = infos.get(0).getFileBytesOffset();
        return offset < 0 ? 0 : offset;
    }

    private List<Object> exportSymbols(Map<String,Object> layout) throws CancelledException {
        if (layout != null) {
            List<Object> preserved = new ArrayList<>();
            for (Object value : array(layout.get("symbols"), "symbols"))
                preserved.add(new LinkedHashMap<>(object(value, "symbol")));
            preserved.sort(Comparator.comparingLong(x->number(object(x,"symbol").get("address")))
                .thenComparing(x->string(object(x,"symbol").get("name")))
                .thenComparing(x->string(object(x,"symbol").get("binding")))
                .thenComparing(x->String.valueOf(object(x,"symbol").get("section"))));
            return preserved;
        }
        List<Symbol> symbols = new ArrayList<>();
        SymbolIterator iterator = currentProgram.getSymbolTable().getAllSymbols(true);
        while (iterator.hasNext()) symbols.add(iterator.next());
        Collections.sort(symbols, Comparator.comparingLong((Symbol s)->s.getAddress().getOffset())
            .thenComparing((Symbol s)->s.getName()).thenComparing(s->s.getSymbolType().toString()));
        List<Object> out = new ArrayList<>();
        for (Symbol symbol : symbols) {
            monitor.checkCancelled();
            if (!symbol.getAddress().isMemoryAddress()) continue;
            Map<String,Object> item=map(); item.put("name",symbol.getName());
            item.put("address",symbol.getAddress().getOffset());
            item.put("binding",symbol.isGlobal()?"external":"local");
            MemoryBlock block=currentProgram.getMemory().getBlock(symbol.getAddress());
            item.put("section",block==null?null:block.getName()); out.add(item);
        }
        return out;
    }

    private List<Object> exportRelocations(Map<String,Object> layout) throws CancelledException {
        relocationIndexesByAddress.clear();
        if (layout != null) {
            List<Object> out = new ArrayList<>();
            long index=0; for (Object value : array(layout.get("relocations"), "relocations")) {
                Map<String,Object> source = object(value, "relocation"), item = map();
                item.put("address", source.get("address")); item.put("kind", source.get("kind"));
                item.put("target", source.get("target")); item.put("addend", source.get("addend"));
                out.add(item);
                relocationIndexesByAddress.computeIfAbsent(number(source.get("address")),ignored->new ArrayList<>()).add(index++);
            }
            out.sort(Comparator.comparingLong(x->number(object(x,"relocation").get("address")))
                .thenComparing(x->string(object(x,"relocation").get("kind")))
                .thenComparing(x->String.valueOf(object(x,"relocation").get("target")))
                .thenComparingLong(x->number(object(x,"relocation").get("addend"))));
            return out;
        }
        List<Relocation> values = new ArrayList<>();
        Iterator<Relocation> iterator = currentProgram.getRelocationTable().getRelocations();
        while (iterator.hasNext()) values.add(iterator.next());
        Collections.sort(values, Comparator.comparingLong((Relocation r)->r.getAddress().getOffset())
            .thenComparingInt(Relocation::getType)
            .thenComparing(r->String.valueOf(r.getSymbolName()))
            .thenComparing(r->Arrays.toString(r.getValues()))
            .thenComparing(r->r.getStatus().toString()));
        List<Object> out = new ArrayList<>();
        for (Relocation relocation : values) {
            monitor.checkCancelled(); Map<String,Object> item=map();
            item.put("address",relocation.getAddress().getOffset());
            item.put("kind",Integer.toString(relocation.getType()));
            item.put("target",relocation.getSymbolName());
            long[] relocationValues=relocation.getValues();
            item.put("addend",relocationValues.length==0?0:relocationValues[0]);
            relocationIndexesByAddress.computeIfAbsent(relocation.getAddress().getOffset(),ignored->new ArrayList<>()).add((long)out.size());out.add(item);
        }
        return out;
    }

    private List<Object> exportFallbackRelocationStatus(Map<String,Object> layout) throws CancelledException {
        List<Object> out=new ArrayList<>();int index=0;for(Object value:array(layout.get("relocations"),"relocations")){
            monitor.checkCancelled();Map<String,Object> expected=object(value,"relocation"),item=map();long addressValue=number(expected.get("address"));
            Address address=currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addressValue);Relocation matched=null;
            for(Relocation relocation:currentProgram.getRelocationTable().getRelocations(address))if(relocation.getType()==number(expected.get("type"))&&Objects.equals(relocation.getSymbolName(),expected.get("target"))&&
                Arrays.equals(relocation.getBytes(),unhex(string(expected.get("original_bytes"))))){matched=relocation;break;}
            item.put("index",index++);item.put("address",addressValue);item.put("status",matched==null?"MISSING":matched.getStatus().toString());
            item.put("type",matched==null?expected.get("type"):matched.getType());item.put("values",matched==null?List.of():longs(matched.getValues()));
            item.put("original_bytes",matched==null?expected.get("original_bytes"):hex(matched.getBytes()));item.put("width",expected.get("width"));
            Instruction owner=currentProgram.getListing().getInstructionContaining(address);Address referenceSource=owner==null?address:owner.getAddress();item.put("reference_source",referenceSource.getOffset());
            TreeSet<Long> targets=new TreeSet<>();TreeSet<String> externalSymbols=new TreeSet<>(),externalLibraries=new TreeSet<>();
            for(Reference reference:currentProgram.getReferenceManager().getReferencesFrom(referenceSource)){if(reference.getToAddress().isMemoryAddress())targets.add(reference.getToAddress().getOffset());
                if(reference instanceof ExternalReference){ExternalReference external=(ExternalReference)reference;externalSymbols.add(external.getLabel());externalLibraries.add(external.getLibraryName());}}
            item.put("reference_targets",new ArrayList<>(targets));item.put("external_symbols",new ArrayList<>(externalSymbols));item.put("external_libraries",new ArrayList<>(externalLibraries));out.add(item);}return out;
    }

    private static List<Long> longs(long[] values){List<Long> out=new ArrayList<>();for(long value:values)out.add(value);return out;}

    private List<Object> exportFunctions(List<Object> summaries) throws Exception {
        List<Function> functions = new ArrayList<>();
        FunctionIterator iterator=currentProgram.getFunctionManager().getFunctions(true);
        while(iterator.hasNext()) {
            Function function = iterator.next();
            if (function.getEntryPoint().isMemoryAddress()) functions.add(function);
        }
        Collections.sort(functions,Comparator.comparingLong(f->f.getEntryPoint().getOffset()));
        DecompInterface decompiler=new DecompInterface();
        if(!decompiler.openProgram(currentProgram)) throw new IOException("decompiler initialization failed");
        try {
            List<Object> out=new ArrayList<>();
            for(Function function:functions){
                monitor.checkCancelled(); Map<String,Object> item=map();
                item.put("address",function.getEntryPoint().getOffset()); item.put("size",function.getBody().getNumAddresses());
                List<String> names=new ArrayList<>();
                for(Symbol symbol:currentProgram.getSymbolTable().getSymbols(function.getEntryPoint())) names.add(symbol.getName());
                Collections.sort(names); item.put("names",names);
                item.put("blocks",exportBlocks(function));
                List<Object> calls=new ArrayList<>();
                item.put("instructions",exportInstructions(function,calls)); item.put("calls",calls);
                item.put("confidence",function.getSymbol().getSource()==SourceType.ANALYSIS?0.75:1.0);
                out.add(item); summaries.add(decompile(function,decompiler));
            }
            return out;
        } finally { decompiler.dispose(); }
    }

    private List<Object> exportBlocks(Function function) throws Exception {
        BasicBlockModel model=new BasicBlockModel(currentProgram);
        CodeBlockIterator iterator=model.getCodeBlocksContaining(function.getBody(),monitor);
        List<CodeBlock> blocks=new ArrayList<>(); while(iterator.hasNext()) blocks.add(iterator.next());
        Collections.sort(blocks,Comparator.comparingLong((CodeBlock b)->b.getFirstStartAddress().getOffset())
            .thenComparing(CodeBlock::getName));
        List<Object> out=new ArrayList<>();
        for(CodeBlock block:blocks){ Map<String,Object> item=map();
            item.put("address",block.getFirstStartAddress().getOffset()); item.put("size",block.getNumAddresses());
            List<Object> successors=new ArrayList<>(); CodeBlockReferenceIterator destinations=block.getDestinations(monitor);
            while(destinations.hasNext()){ CodeBlockReference edge=destinations.next();
                if(!edge.getDestinationAddress().isMemoryAddress()) continue;
                Map<String,Object> successor=map(); successor.put("target",edge.getDestinationAddress().getOffset());
                successor.put("kind",edge.getFlowType().toString()); successors.add(successor); }
            successors.sort(Comparator.comparingLong(x->number(object(x,"successor").get("target")))
                .thenComparing(x->string(object(x,"successor").get("kind"))));
            item.put("successors",successors); out.add(item); }
        return out;
    }

    private List<Object> exportInstructions(Function function,List<Object> calls) throws Exception {
        List<Object> out=new ArrayList<>(); InstructionIterator iterator=currentProgram.getListing().getInstructions(function.getBody(),true);
        while(iterator.hasNext()){ monitor.checkCancelled(); Instruction instruction=iterator.next(); Map<String,Object> item=map();
            byte[] instructionBytes=instruction.getBytes();long instructionStart=instruction.getAddress().getOffset();
            if(instructionBytes.length==0)throw new IOException("zero-length instruction at "+instruction.getAddress());
            long instructionEnd=Math.addExact(instructionStart,instructionBytes.length);
            item.put("address",instructionStart); item.put("bytes",hex(instructionBytes));
            item.put("mnemonic",instruction.getMnemonicString());
            List<String> operands=new ArrayList<>(); for(int i=0;i<instruction.getNumOperands();i++) operands.add(instruction.getDefaultOperandRepresentation(i));
            String operandText=String.join(", ",operands); item.put("operands",operandText); item.put("normalized_operands",operandText);
            TreeSet<Long> relocationIndexes=new TreeSet<>();for(List<Long> indexes:relocationIndexesByAddress.subMap(instructionStart,true,instructionEnd,false).values())relocationIndexes.addAll(indexes);
            item.put("relocations",new ArrayList<>(relocationIndexes)); out.add(item);
            for(Reference reference:instruction.getReferencesFrom()){
                if(reference.getReferenceType().isCall()){ Map<String,Object> call=map(); call.put("address",instruction.getAddress().getOffset());
                    call.put("target",reference.getToAddress().isMemoryAddress()?reference.getToAddress().getOffset():null);
                    Symbol target=currentProgram.getSymbolTable().getPrimarySymbol(reference.getToAddress()); call.put("name",target==null?null:target.getName()); calls.add(call); }} }
        calls.sort(Comparator.comparingLong((Object x)->number(object(x,"call").get("address")))
            .thenComparing(x->String.valueOf(object(x,"call").get("target")))
            .thenComparing(x->String.valueOf(object(x,"call").get("name")))); return out;
    }

    private ReferenceExport exportAllReferences(ReferenceManager referenceManager)
            throws CancelledException {
        TreeMap<ReferenceKey,ReferenceAggregate> collected = new TreeMap<>();
        AddressIterator sources = referenceManager.getReferenceSourceIterator(currentProgram.getMemory(), true);
        while (sources.hasNext()) {
            monitor.checkCancelled();
            Address source = sources.next();
            for (Reference reference : referenceManager.getReferencesFrom(source)) {
                Address target = reference.getToAddress();
                Long normalizedTarget = target.isMemoryAddress() ? target.getOffset() : null;
                ReferenceKey key = new ReferenceKey(source.getOffset(), normalizedTarget,
                    reference.getReferenceType().toString());
                ReferenceAggregate aggregate = collected.computeIfAbsent(key,
                    ignored -> new ReferenceAggregate(key));
                aggregate.add(reference);
            }
        }
        return new ReferenceExport(collected);
    }

    private List<Object> exportImports(List<Object> ignored) throws CancelledException {
        List<Object> out=new ArrayList<>(); SymbolIterator iterator=currentProgram.getSymbolTable().getExternalSymbols();
        while(iterator.hasNext()){ monitor.checkCancelled(); Symbol symbol=iterator.next(); Map<String,Object> item=map();
            item.put("name",symbol.getName()); item.put("address",symbol.getAddress().isMemoryAddress()?symbol.getAddress().getOffset():null); out.add(item); }
        out.sort(Comparator.comparing((Object x)->string(object(x,"import").get("name")))
            .thenComparing(x->String.valueOf(object(x,"import").get("address")))); return out;
    }

    private List<Object> exportStrings(List<Object> ignored) throws CancelledException {
        List<Object> out=new ArrayList<>(); DataIterator iterator=currentProgram.getListing().getDefinedData(true);
        while(iterator.hasNext()){ monitor.checkCancelled(); Data data=iterator.next(); StringDataInstance instance=StringDataInstance.getStringDataInstance(data);
            if(!StringDataInstance.isString(data)) continue;
            if(instance==null||instance==StringDataInstance.NULL_INSTANCE) throw new IllegalStateException("string instance unavailable");
            String value=instance.getStringValue(); if(value==null) throw new IllegalStateException("string decode failed");
            Map<String,Object> item=map(); item.put("address",data.getAddress().getOffset()); item.put("value",value);
            item.put("encoding",instance.getCharsetName()); out.add(item); }
        out.sort(Comparator.comparingLong(x->number(object(x,"string").get("address")))); return out;
    }

    private Map<String,Object> decompile(Function function,DecompInterface decompiler) {
        Map<String,Object> summary=map(); summary.put("address",function.getEntryPoint().getOffset());
        summary.put("c",null); summary.put("status","failed"); summary.put("message",null);
        TreeMap<String,Long> counts=new TreeMap<>(); summary.put("pcode_operations",counts);
        DecompileResults result;
        try {
            result=decompiler.decompileFunction(function,60,monitor);
        } catch (RuntimeException error) {
            summary.put("message",bounded(error.getClass().getSimpleName()+": "+error.getMessage(),MAX_DECOMPILE_MESSAGE));
            return summary;
        }
        if(result==null){summary.put("message","decompiler returned no result");return summary;}
        HighFunction high=result.getHighFunction();
        if(high!=null){Iterator<? extends PcodeOp> iterator=high.getPcodeOps();while(iterator.hasNext()){
            PcodeOp op=iterator.next();String name=op.getMnemonic();counts.put(name,counts.getOrDefault(name,0L)+1);}}
        String warning=bounded(result.getErrorMessage(),MAX_DECOMPILE_MESSAGE);
        summary.put("message",warning);
        if(result.isTimedOut()){summary.put("status","timeout");return summary;}
        if(!result.decompileCompleted()){summary.put("status","failed");return summary;}
        DecompiledFunction recovered=result.getDecompiledFunction();
        if(recovered==null||recovered.getC()==null){summary.put("status","missing-c");return summary;}
        summary.put("c",bounded(recovered.getC(),MAX_DECOMPILED_C));
        summary.put("status","success"); return summary;
    }

    private static String bounded(String value,int limit){if(value==null)return null;
        String normalized=value.replace("\r\n", "\n").replace("\r", "\n");
        return normalized.length()<=limit?normalized:normalized.substring(0,limit)+"\n[truncated]\n";}

    private static final class ReferenceKey implements Comparable<ReferenceKey> {
        final long source; final Long target; final String kind;
        ReferenceKey(long source,Long target,String kind){this.source=source;this.target=target;this.kind=kind;}
        public int compareTo(ReferenceKey other){int value=Long.compare(source,other.source);if(value!=0)return value;
            if(target==null&&other.target!=null)return 1;if(target!=null&&other.target==null)return -1;
            if(target!=null&&(value=Long.compare(target,other.target))!=0)return value;return kind.compareTo(other.kind);}
    }

    private static final class ReferenceAggregate {
        final ReferenceKey key; final TreeSet<Integer> operandIndexes=new TreeSet<>();
        final TreeSet<String> sourceTypes=new TreeSet<>(),sourceSpaces=new TreeSet<>(),targetSpaces=new TreeSet<>(),targetDisplays=new TreeSet<>();
        boolean primary,external;
        ReferenceAggregate(ReferenceKey key){this.key=key;}
        void add(Reference reference){operandIndexes.add(reference.getOperandIndex());sourceTypes.add(reference.getSource().toString());
            sourceSpaces.add(reference.getFromAddress().getAddressSpace().getName());
            targetSpaces.add(reference.getToAddress().getAddressSpace().getName());targetDisplays.add(reference.getToAddress().toString());
            primary|=reference.isPrimary();external|=reference.isExternalReference();}
        Map<String,Object> normalized(){Map<String,Object> value=map();value.put("address",key.source);value.put("target",key.target);value.put("kind",key.kind);return value;}
        Map<String,Object> metadata(int index){Map<String,Object> value=map();value.put("index",index);value.put("operand_indexes",new ArrayList<>(operandIndexes));
            value.put("source_types",new ArrayList<>(sourceTypes));value.put("source_spaces",new ArrayList<>(sourceSpaces));
            value.put("target_space",new ArrayList<>(targetSpaces));value.put("target_displays",new ArrayList<>(targetDisplays));
            value.put("primary",primary);value.put("external",external);return value;}
    }

    private static final class ReferenceExport {
        final List<Object> normalized=new ArrayList<>(),metadata=new ArrayList<>();
        final TreeMap<Long,List<Integer>> indexesBySource=new TreeMap<>();
        ReferenceExport(TreeMap<ReferenceKey,ReferenceAggregate> collected){int index=0;for(ReferenceAggregate value:collected.values()){
            normalized.add(value.normalized());metadata.add(value.metadata(index));indexesBySource.computeIfAbsent(value.key.source,ignored->new ArrayList<>()).add(index++);}}
        List<Object> instructionIndexes(Program program){List<Object> out=new ArrayList<>();for(Map.Entry<Long,List<Integer>> entry:indexesBySource.entrySet()){
            Address address=program.getAddressFactory().getDefaultAddressSpace().getAddress(entry.getKey());
            if(program.getListing().getInstructionAt(address)==null)continue;Map<String,Object> value=map();value.put("address",entry.getKey());
            value.put("reference_indexes",entry.getValue());out.add(value);}return out;}
    }

    private static void writeAtomically(Path output,Object value) throws Exception {
        Path absolute=output.toAbsolutePath().normalize(); Files.createDirectories(absolute.getParent());
        if(Files.exists(absolute)) throw new IOException("output already exists");
        Path temporary=Files.createTempFile(absolute.getParent(),"."+absolute.getFileName()+".",".native-write");
        try(BufferedWriter writer=Files.newBufferedWriter(temporary,StandardCharsets.UTF_8,StandardOpenOption.TRUNCATE_EXISTING)){
            JsonWriter.write(writer,value); writer.write('\n'); }
        try { Files.move(temporary,absolute,StandardCopyOption.ATOMIC_MOVE); }
        catch(AtomicMoveNotSupportedException error){ Files.deleteIfExists(temporary); throw error; }
    }

    private static String sha256(Path path)throws Exception{ MessageDigest digest=MessageDigest.getInstance("SHA-256");
        try(InputStream in=Files.newInputStream(path)){byte[] b=new byte[1024*1024];int n;while((n=in.read(b))>=0)if(n>0)digest.update(b,0,n);}return hex(digest.digest());}
    private static String hex(byte[] bytes){StringBuilder b=new StringBuilder(bytes.length*2);for(byte value:bytes)b.append(String.format(Locale.ROOT,"%02X",value&255));return b.toString();}
    private static Map<String,Object> map(){return new LinkedHashMap<>();}
    @SuppressWarnings("unchecked") private static Map<String,Object> object(Object value,String where){if(!(value instanceof Map))throw new IllegalArgumentException(where+" is not an object");return (Map<String,Object>)value;}
    @SuppressWarnings("unchecked") private static List<Object> array(Object value,String where){if(!(value instanceof List))throw new IllegalArgumentException(where+" is not an array");return (List<Object>)value;}
    private static String string(Object value){if(!(value instanceof String))throw new IllegalArgumentException("value is not a string");return (String)value;}
    private static long number(Object value){if(!(value instanceof Number))throw new IllegalArgumentException("value is not a number");return ((Number)value).longValue();}

    private static final class Args {
        private static final Set<String> COMMON_OPTIONS=Set.of("--input","--size","--sha256","--language");
        private static final Set<String> PREPARE_OPTIONS=Set.of("--input","--size","--sha256","--language","--layout");
        private static final Set<String> EXPORT_OPTIONS=Set.of("--input","--size","--sha256","--language","--output","--layout");
        final String mode; final Map<String,String> values;
        Args(String mode,Map<String,String> values){this.mode=mode;this.values=values;}
        String required(String key){String value=values.get(key);if(value==null||value.isEmpty())throw new IllegalArgumentException("missing "+key);return value;}
        static Args parse(String[] args){if(args.length<1)throw new IllegalArgumentException("missing mode");String mode=args[0];
            if(!"prepare".equals(mode)&&!"export".equals(mode))throw new IllegalArgumentException("invalid mode: "+mode);
            Set<String> allowed="prepare".equals(mode)?PREPARE_OPTIONS:EXPORT_OPTIONS;Map<String,String> values=new HashMap<>();
            for(int i=1;i<args.length;){String option=args[i++];if(!option.startsWith("--")||!allowed.contains(option))throw new IllegalArgumentException("unknown option or mode-incompatible option (boolean options are unsupported): "+option);
                if(i>=args.length||args[i].startsWith("--"))throw new IllegalArgumentException("missing value for "+option);
                if(values.put(option,args[i++])!=null)throw new IllegalArgumentException("duplicate option: "+option);}
            Set<String> required=new HashSet<>(COMMON_OPTIONS);required.add("prepare".equals(mode)?"--layout":"--output");
            if(!values.keySet().containsAll(required))throw new IllegalArgumentException("missing value for required option");
            try{long size=Long.parseLong(values.get("--size"));if(size<0)throw new NumberFormatException();}catch(NumberFormatException error){throw new IllegalArgumentException("invalid --size",error);}
            if(!values.get("--sha256").matches("(?i)[0-9a-f]{64}"))throw new IllegalArgumentException("invalid --sha256");
            if(!LANGUAGE.equals(values.get("--language")))throw new IllegalArgumentException("invalid --language");
            return new Args(mode,values);}
    }

    private static final class JsonWriter {
        static void write(Writer out,Object value)throws IOException{
            if(value==null){out.write("null");return;} if(value instanceof String){string(out,(String)value);return;}
            if(value instanceof Boolean){out.write(value.toString());return;} if(value instanceof Number){
                if((value instanceof Double&&!Double.isFinite((Double)value))||(value instanceof Float&&!Float.isFinite((Float)value)))throw new IOException("non-finite JSON number");
                out.write(String.format(Locale.ROOT,"%s",value));return;}
            if(value instanceof Map){out.write('{');boolean first=true;List<String> keys=new ArrayList<>();for(Object key:((Map<?,?>)value).keySet())keys.add((String)key);Collections.sort(keys);
                for(String key:keys){if(!first)out.write(',');first=false;string(out,key);out.write(':');write(out,((Map<?,?>)value).get(key));}out.write('}');return;}
            if(value instanceof Iterable){out.write('[');boolean first=true;for(Object item:(Iterable<?>)value){if(!first)out.write(',');first=false;write(out,item);}out.write(']');return;}
            throw new IOException("unsupported JSON value "+value.getClass().getName());}
        static void string(Writer out,String value)throws IOException{out.write('"');for(int i=0;i<value.length();i++){char c=value.charAt(i);switch(c){
            case '"':out.write("\\\"");break;case '\\':out.write("\\\\");break;case '\b':out.write("\\b");break;case '\f':out.write("\\f");break;
            case '\n':out.write("\\n");break;case '\r':out.write("\\r");break;case '\t':out.write("\\t");break;default:if(c<0x20)out.write(String.format(Locale.ROOT,"\\u%04X",(int)c));else out.write(c);}}out.write('"');}
    }

    // Strict, dependency-free parser used only for the host-owned fallback layout.
    private static final class JsonParser {
        final String text; int at; JsonParser(String text){this.text=text;}
        Object parse(){Object value=value();space();if(at!=text.length())fail("trailing data");return value;}
        Object value(){space();if(at>=text.length())return fail("unexpected end");char c=text.charAt(at);if(c=='{')return object();if(c=='[')return array();if(c=='"')return string();
            if(c=='t'){literal("true");return true;}if(c=='f'){literal("false");return false;}if(c=='n'){literal("null");return null;}return number();}
        Map<String,Object> object(){at++;Map<String,Object> out=new LinkedHashMap<>();space();if(take('}'))return out;while(true){space();String key=string();space();need(':');
            if(out.put(key,value())!=null)fail("duplicate key");space();if(take('}'))return out;need(',');}}
        List<Object> array(){at++;List<Object> out=new ArrayList<>();space();if(take(']'))return out;while(true){out.add(value());space();if(take(']'))return out;need(',');}}
        String string(){need('"');StringBuilder out=new StringBuilder();while(at<text.length()){char c=text.charAt(at++);if(c=='"')return out.toString();if(c<' ')fail("control in string");
            if(c!='\\'){out.append(c);continue;}if(at>=text.length())fail("bad escape");char e=text.charAt(at++);switch(e){case '"':case '\\':case '/':out.append(e);break;
            case 'b':out.append('\b');break;case 'f':out.append('\f');break;case 'n':out.append('\n');break;case 'r':out.append('\r');break;case 't':out.append('\t');break;
            case 'u':if(at+4>text.length())fail("short unicode escape");out.append((char)Integer.parseInt(text.substring(at,at+4),16));at+=4;break;default:fail("bad escape");}}return fail("unterminated string");}
        Long number(){int start=at;if(take('-')){}if(at>=text.length()||!Character.isDigit(text.charAt(at)))return fail("bad number");while(at<text.length()&&Character.isDigit(text.charAt(at)))at++;
            if(at<text.length()&&(text.charAt(at)=='.'||text.charAt(at)=='e'||text.charAt(at)=='E'))return fail("layout numbers must be integers");try{return Long.parseLong(text.substring(start,at));}catch(NumberFormatException e){return fail("integer out of range");}}
        void literal(String value){if(!text.startsWith(value,at))fail("bad literal");at+=value.length();}void space(){while(at<text.length()&&Character.isWhitespace(text.charAt(at)))at++;}
        boolean take(char c){if(at<text.length()&&text.charAt(at)==c){at++;return true;}return false;}void need(char c){if(!take(c))fail("expected "+c);}
        <T>T fail(String message){throw new IllegalArgumentException(message+" at "+at);}
    }
}
