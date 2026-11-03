// N24: a C++ METHOD call on a call result (`f()->m()`) is no slot call, even when a function-pointer field of the same name exists
struct Ops { const char* k; void (*mr_write)(int); };
static void ops_mr_write(int x) { (void)x; }
static const Ops kMrOps = { "o", ops_mr_write };
struct MrWidget { void mr_write(int x); };
void MrWidget::mr_write(int x) { (void)x; }
MrWidget* current_mr_widget();
void mr_paint() { current_mr_widget()->mr_write(1); }
