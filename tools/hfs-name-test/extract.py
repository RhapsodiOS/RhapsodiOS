"""Print the parts of UnicodeWrappers.c that mangle_test.c is built from.

UnicodeWrappers.c holds Mac Roman bytes, so it is read as latin-1.  What is
printed must be plain ASCII, because run-tests.sh sends it to the build box
as a heredoc.
"""
import re
import sys

# In dependency order, so that no prototypes are needed.
FUNCTIONS = [
    "HexStringToInteger",
    "CountFilenameExtensionChars",
    "GetEmbeddedFileID",
    "ConvertUnicodeToUTF8",
    "GetMangledFileIDString",
    "GetMangledNameExtension",
    "ConvertUnicodeToUTF8Mangled",
]
MACROS = ["IsHexDigit", "EXTENSIONCHAR"]


def main(path):
    src = open(path, "rb").read().decode("latin-1")
    parts = []
    m = re.search(r"kMaxFileExtensionChars\s*=\s*(\d+)", src)
    if not m:
        sys.exit("kMaxFileExtensionChars not found")
    parts.append("enum { kMaxFileExtensionChars = %s };" % m.group(1))
    for name in MACROS:
        m = re.search(r"^#define\s+%s\b.*$" % name, src, re.M)
        if not m:
            sys.exit("macro %s not found" % name)
        parts.append(m.group(0))
    for name in FUNCTIONS:
        # The return-type line, then the name at the start of a line, up to
        # the first "}" in column 0.
        m = re.search(r"^[^\n]*\n%s ?\([\s\S]*?\n\}" % name, src, re.M)
        if not m:
            sys.exit("function %s not found" % name)
        parts.append(m.group(0))
    text = "\n\n".join(parts) + "\n"
    if any(ord(c) > 0x7F for c in text):
        sys.exit("what was extracted is not plain ASCII")
    sys.stdout.write(text)


if __name__ == "__main__":
    main(sys.argv[1])
