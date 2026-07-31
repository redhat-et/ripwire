// util/strings.cpp — cluster E (util/strings). Dense intra-cluster chain.

int strStepE1() { return 5; }
int strStepE2() { return strStepE1() + strStepE1(); }
int strStepE3() { return strStepE2() + strStepE1(); }
int strStepE4() { return strStepE3() + strStepE2() + strStepE1(); }
int stringsRun() { return strStepE4() + strStepE3() + strStepE2(); }
