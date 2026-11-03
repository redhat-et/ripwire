#include "row.h"
void Row_display(const Row* this) { As_Row(this)->writeField(this, 1); }
void Other_display(const Row* this) { As_Other(this)->writeField(this, 2); }
void Klass_display(const Row* this) { Get_Klass(this)->writeField(this, 3); }
void Fn_display(const Row* this) { row_class_of(this)->writeField(this, 4); }
