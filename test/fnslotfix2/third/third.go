package third

import "example.com/m/enlist"

func viaQualified() {}
func litFn()        {}

var lit = enlist.Task{Do: litFn}

func init() { enlist.Enlist(viaQualified) }
