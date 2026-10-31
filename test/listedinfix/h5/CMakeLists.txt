add_executable(demo main.c)
#[[
add_library(old
  widget-alpha.c
  widget-beta.c)
]]
list(REMOVE_ITEM SRCS
  widget-gamma.c
  widget-delta.c)
add_library(live
  widget-epsilon.c
  widget-zeta.c # widget-eta.c is gone
  )
add_library(more other.c)  # widget-alpha.c
