// Fixture for vendorpatchcheck: multi-byte UTF-8 (emoji) inside a raw #"..."# string.
// Pre-patch, the vendored Swift scanner truncates lexer->lookahead (int32 codepoint) into a
// uint8 implicitly while eating raw_str_part, which aborts the G1 integer-sanitizer stack.
func rawStringWithEmoji() -> String {
    let banner = #"deploy ok 🚀 party 🎉 done"#
    let nested = ##"hash ## inside ✅ still raw"##
    return banner + nested
}
