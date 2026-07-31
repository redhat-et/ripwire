// util/math.cpp — cluster F (util/math), with one thin edge into the strings cluster (stringsRun) so the two
// util clusters share a top module but stay distinct level-0 communities.

int stringsRun();   // cross-cluster (still in util/)

int mathStepF1() { return 6; }
int mathStepF2() { return mathStepF1() + mathStepF1(); }
int mathStepF3() { return mathStepF2() + mathStepF1(); }
int mathStepF4() { return mathStepF3() + mathStepF2() + mathStepF1(); }
int mathRun()    { return mathStepF4() + mathStepF3() + stringsRun(); }
