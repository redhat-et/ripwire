/* process table walkers: decoys that repeat the question words (scan, walk, process, tables, collect, gather). */
#include "table.h"

/* scan and walk the process tables (Cpu): collect and gather process table rows */
int ProcessTable_scanWalkGatherCpu(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Mem): collect and gather process table rows */
int ProcessTable_scanWalkGatherMem(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Io): collect and gather process table rows */
int ProcessTable_scanWalkGatherIo(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Net): collect and gather process table rows */
int ProcessTable_scanWalkGatherNet(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Disk): collect and gather process table rows */
int ProcessTable_scanWalkGatherDisk(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Swap): collect and gather process table rows */
int ProcessTable_scanWalkGatherSwap(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Load): collect and gather process table rows */
int ProcessTable_scanWalkGatherLoad(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Uptime): collect and gather process table rows */
int ProcessTable_scanWalkGatherUptime(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Task): collect and gather process table rows */
int ProcessTable_scanWalkGatherTask(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}

/* scan and walk the process tables (Thread): collect and gather process table rows */
int ProcessTable_scanWalkGatherThread(Table* processTables) {
    return Table_rowCount(processTables) + Table_collectRows(processTables);
}
