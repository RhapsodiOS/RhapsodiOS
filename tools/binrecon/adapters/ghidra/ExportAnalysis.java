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
    private void prepare(Args args) throws Exception {
        verifyLanguage();
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
            String name = string(section.get("name"));
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
                block = memory.createInitializedBlock(name, space.getAddress(address),
                    size, (byte)0, monitor, false);
            }
            String permissions = string(section.get("permissions"));
            block.setRead(permissions.contains("r"));
            block.setWrite(permissions.contains("w"));
            block.setExecute(permissions.contains("x"));
        }
        SymbolTable symbols = currentProgram.getSymbolTable();
        for (Object item : array(layout.get("symbols"), "symbols")) {
            Map<String,Object> symbol = object(item, "symbol");
            symbols.createLabel(space.getAddress(number(symbol.get("address"))),
                string(symbol.get("name")), SourceType.IMPORTED);
        }
        for (Object item : array(layout.get("entry_points"), "entry_points")) {
            Map<String,Object> entry = object(item, "entry point");
            Address address = space.getAddress(number(entry.get("address")));
            symbols.createLabel(address, string(entry.get("name")), SourceType.IMPORTED);
            symbols.addExternalEntryPoint(address);
        }
    }

    private void export(Args args) throws Exception {
        verifyLanguage();
        if (currentProgram.getMemory().getBlocks().length == 0)
            throw new IOException("program has no memory layout");
        String executablePath = currentProgram.getExecutablePath();
        if (executablePath == null || !Files.isSameFile(Paths.get(executablePath),
                Paths.get(args.required("--input")))) {
            throw new IOException("program executable identity does not match input");
        }
        if (args.values.containsKey("--layout")) verifyPreparedLayout(args);
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
        analyzer.put("version", Application.getApplicationVersion());
        analyzer.put("invocation", "analyzeHeadless ExportAnalysis.java");
        root.put("analyzer", analyzer);

        root.put("sections", exportSections());
        root.put("symbols", exportSymbols());
        root.put("relocations", exportRelocations());
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
        extensions.put("ghidra", ghidra); root.put("extensions", extensions);
        writeAtomically(Paths.get(args.required("--output")), root);
    }

    private void verifyPreparedLayout(Args args) throws Exception {
        @SuppressWarnings("unchecked")
        Map<String,Object> layout = (Map<String,Object>)new JsonParser(Files.readString(
            Paths.get(args.required("--layout")), StandardCharsets.UTF_8)).parse();
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
            if (!block.getName().equals(string(section.get("name"))) ||
                    block.getStart().getOffset() != number(section.get("address")) ||
                    block.getSize() != number(section.get("size")) ||
                    block.isRead() != permissions.contains("r") ||
                    block.isWrite() != permissions.contains("w") ||
                    block.isExecute() != permissions.contains("x"))
                throw new IOException("prepared memory layout mismatch");
        }
    }

    private List<Object> exportSections() throws Exception {
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
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[1024 * 1024]; long done = 0;
            while (done < block.getSize()) {
                int count = (int)Math.min(buffer.length, block.getSize() - done);
                Address at = block.getStart().add(done);
                if (block.isInitialized()) currentProgram.getMemory().getBytes(at, buffer, 0, count);
                else Arrays.fill(buffer, 0, count, (byte)0);
                digest.update(buffer, 0, count); done += count;
            }
            item.put("sha256", hex(digest.digest())); out.add(item);
        }
        return out;
    }

    private long sourceOffset(MemoryBlock block) {
        List<MemoryBlockSourceInfo> infos = block.getSourceInfos();
        if (infos.isEmpty()) return 0;
        long offset = infos.get(0).getFileBytesOffset();
        return offset < 0 ? 0 : offset;
    }

    private List<Object> exportSymbols() throws CancelledException {
        List<Symbol> symbols = new ArrayList<>();
        SymbolIterator iterator = currentProgram.getSymbolTable().getAllSymbols(true);
        while (iterator.hasNext()) symbols.add(iterator.next());
        Collections.sort(symbols, Comparator.comparingLong((Symbol s)->s.getAddress().getOffset())
            .thenComparing(Symbol::getName).thenComparing(s->s.getSymbolType().toString()));
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

    private List<Object> exportRelocations() throws CancelledException {
        List<Relocation> values = new ArrayList<>();
        Iterator<Relocation> iterator = currentProgram.getRelocationTable().getRelocations();
        while (iterator.hasNext()) values.add(iterator.next());
        Collections.sort(values, Comparator.comparingLong((Relocation r)->r.getAddress().getOffset())
            .thenComparingInt(Relocation::getType)
            .thenComparing(r->String.valueOf(r.getSymbolName())));
        List<Object> out = new ArrayList<>();
        for (Relocation relocation : values) {
            monitor.checkCancelled(); Map<String,Object> item=map();
            item.put("address",relocation.getAddress().getOffset());
            item.put("kind",Integer.toString(relocation.getType()));
            item.put("target",relocation.getSymbolName());
            long[] relocationValues=relocation.getValues();
            item.put("addend",relocationValues.length==0?0:relocationValues[0]); out.add(item);
        }
        return out;
    }

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
            successors.sort(Comparator.comparingLong(x->number(object(x,"successor").get("target"))));
            item.put("successors",successors); out.add(item); }
        return out;
    }

    private List<Object> exportInstructions(Function function,List<Object> calls) throws Exception {
        List<Object> out=new ArrayList<>(); InstructionIterator iterator=currentProgram.getListing().getInstructions(function.getBody(),true);
        while(iterator.hasNext()){ monitor.checkCancelled(); Instruction instruction=iterator.next(); Map<String,Object> item=map();
            item.put("address",instruction.getAddress().getOffset()); item.put("bytes",hex(instruction.getBytes()));
            item.put("mnemonic",instruction.getMnemonicString());
            List<String> operands=new ArrayList<>(); for(int i=0;i<instruction.getNumOperands();i++) operands.add(instruction.getDefaultOperandRepresentation(i));
            String operandText=String.join(", ",operands); item.put("operands",operandText); item.put("normalized_operands",operandText);
            List<Long> relocations=new ArrayList<>();
            for(Relocation relocation:currentProgram.getRelocationTable().getRelocations(instruction.getAddress())) relocations.add(relocation.getAddress().getOffset());
            Collections.sort(relocations); item.put("relocations",relocations); out.add(item);
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
        AddressIterator sources = referenceManager.getReferenceSourceIterator((AddressSetView)null, true);
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

    private Map<String,Object> decompile(Function function,DecompInterface decompiler) throws Exception {
        DecompileResults result=decompiler.decompileFunction(function,60,monitor);
        if(result==null) throw new IOException("decompiler returned no result at "+function.getEntryPoint());
        if(!result.decompileCompleted()||result.getHighFunction()==null){
            String reason=result.isTimedOut()?"timeout":String.valueOf(result.getErrorMessage());
            throw new IOException("decompile failed at "+function.getEntryPoint()+": "+reason);
        }
        DecompiledFunction recovered=result.getDecompiledFunction();
        if(recovered==null||recovered.getC()==null) throw new IOException("decompiler returned no C at "+function.getEntryPoint());
        HighFunction high=result.getHighFunction(); TreeMap<String,Long> counts=new TreeMap<>(); Iterator<PcodeOp> iterator=high.getPcodeOps();
        while(iterator.hasNext()){ PcodeOp op=iterator.next(); String name=op.getMnemonic(); counts.put(name,counts.getOrDefault(name,0L)+1); }
        Map<String,Object> summary=map(); summary.put("address",function.getEntryPoint().getOffset());
        summary.put("c",recovered.getC().replace("\r\n", "\n").replace("\r", "\n"));
        String warning=result.getErrorMessage();
        summary.put("status","success");
        summary.put("message",warning==null?null:warning.replace("\r\n", "\n").replace("\r", "\n"));
        summary.put("pcode_operations",counts); return summary;
    }

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
