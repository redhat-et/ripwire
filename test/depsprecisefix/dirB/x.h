#pragma once
// dirB's x.h — the DECOY. Same basename `x.h` as dirA/x.h, DIFFERENT directory. consumer.cpp does NOT
// include this; the old basename resolver linked it anyway (wrong file->file edge). Precise must NOT.
inline int beta( void ) { return 2; }
