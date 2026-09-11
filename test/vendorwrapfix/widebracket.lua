-- A long-bracket string opened with exactly 256 '=' — the first count a uint8_t cannot hold.
-- Before lua/001-delimiter-count-cast the ++count at scanner.c:32 truncated and aborted the G1
-- stack. ABORT-ARM ONLY, for the same measured reason as widehash.rs.
function narrowCounterWrapLua()
  local s = [================================================================================================================================================================================================================================================================[ two hundred and fifty six equals ]================================================================================================================================================================================================================================================================]
  return s
end
