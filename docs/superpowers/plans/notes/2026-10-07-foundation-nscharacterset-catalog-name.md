# Foundation NSCharacterSet auxiliary catalog path (2026-10-07)

Paired IDA decompilation of `+[NSConcreteMutableCharacterSet
_findDictOrBitmapSetNamed:]` and `+[NSCharacterSet
characterSetWithContentsOfFile:]` shows both targets append
`SystemCharacterSetAux.dict` beneath the Foundation `Resources/CharacterSets`
directory when loading named dictionary-backed sets. The string is present in
both target databases: i386 at `0x425fe980` and PPC at `0x426218bc`.

The source used `CharacterSets.dict` at both lookup sites, a catalog name not
present in the target string table. Both paths now use the IDA-confirmed
`SystemCharacterSetAux.dict` name. Function references: i386 `_find...` at
`0x4258698c` and `characterSetWithContentsOfFile:` at `0x42549278`; PPC
`_find...` at `0x4254b808` and `characterSetWithContentsOfFile:` at
`0x4253fc70`. Static source and whitespace checks only; no tests or builds
were run.
