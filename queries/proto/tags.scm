; ripwire Protocol Buffers tags — written for ripwire (.proto), against coder3101/tree-sitter-proto v0.6.0's
; node types (proto2, proto3 and editions). Gate: test/protoindexcheck.sh.
;
; A .proto file is a SCHEMA: the Rust (prost), Go (protoc-gen-go), C++, Python and TS modules a build generates
; from it are usually not in the tree, so these definitions are the only place a generated name is defined.
; Captured: message (and a proto2 group), enum, oneof, service, rpc, enum value. The definition node is the whole
; construct, so --expand prints the message or enum body. Nesting is the scope (ingest_names.h
; protoEnclosingScopeOf): a nested message, an enum value, a oneof and an rpc carry their owner's name.
;
; NOT captured, disclosed: message FIELDS (`Type function_type = 1;`, a map field), the `package`, `import`,
; `option` and `extend` statements, and every type REFERENCE. There are no @reference captures, so a .proto file
; has no call edges and no file edges (langfacts.h FileEdges::NotApplicable). Comments and string literals are
; grammar nodes, so a keyword inside them (`// message Fake`, `option x = "enum Y"`) never matches a pattern below.

(message
  (message_name
    (identifier) @name)) @definition.class

(group
  (message_name
    (identifier) @name)) @definition.class

(enum
  (enum_name
    (identifier) @name)) @definition.class

(oneof
  (identifier) @name) @definition.class

(service
  (service_name
    (identifier) @name)) @definition.interface

(rpc
  (rpc_name
    (identifier) @name)) @definition.method

(enum_field
  (identifier) @name) @definition.constant
