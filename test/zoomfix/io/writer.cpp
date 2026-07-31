// io/writer.cpp — cluster D (the io/writer sub-system), with one thin edge into the reader cluster
// (readerRun) so reader+writer share a top module but stay distinct level-0 communities.

int readerRun();   // cross-cluster (still in io/)

int writeStepD1() { return 4; }
int writeStepD2() { return writeStepD1() + writeStepD1(); }
int writeStepD3() { return writeStepD2() + writeStepD1(); }
int writeStepD4() { return writeStepD3() + writeStepD2() + writeStepD1(); }
int writerRun()   { return writeStepD4() + writeStepD3() + readerRun(); }
