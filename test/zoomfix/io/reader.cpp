// io/reader.cpp — cluster C (the io/reader sub-system). Dense intra-cluster chain.

int readStepC1() { return 3; }
int readStepC2() { return readStepC1() + readStepC1(); }
int readStepC3() { return readStepC2() + readStepC1(); }
int readStepC4() { return readStepC3() + readStepC2() + readStepC1(); }
int readerRun()  { return readStepC4() + readStepC3() + readStepC2(); }
