# hostile markdown fixture

## </script><script>alert(1)

A heading engineered to look like a script-tag breakout, to make sure --html embedding
escapes it correctly instead of splicing it raw into an inline <script> block.

## emoji heading 🔥 中文标题

A second heading mixing an emoji with CJK characters, to exercise multi-byte UTF-8
handling end to end (parse -> rank -> serialize).
