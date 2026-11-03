/* FN-SLOT S2 (c): htop's class tables — nested designated literals and a macro cast receiver */
typedef struct RowClass_ { const char* name; void (*writeField)(const void* r, int f); } RowClass;
typedef struct ProcessClass_ { const RowClass super; int (*compare)(int); } ProcessClass;
typedef struct OtherClass_ { void (*writeField)(const void* r, int f); } OtherClass;
typedef struct Row_ { const void* klass; } Row;
#define As_Row(this_)    ((const RowClass*)((this_)->klass))
#define As_Other(this_)  ((const OtherClass*)((this_)->klass))
#define Get_Klass(this_) ((this_)->klass)
const RowClass* row_class_of(const Row* r);
