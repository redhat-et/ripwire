// app.cpp — the top-level orchestrator. It calls one entry point in EACH subsystem (core/io/util), creating
// CROSS-MODULE bridge edges so --zoom's bridge section is exercised on the fixture.

int schedRun();    // core/
int writerRun();   // io/
int mathRun();     // util/

int appMain()
{
    return schedRun() + writerRun() + mathRun();
}
