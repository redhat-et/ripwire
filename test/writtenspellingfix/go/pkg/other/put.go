package other

import be "example.com/m/pkg/batcheval"

func Put(x int) int { return be.Put(x) + goOtherPutHelper() }

func goOtherPutHelper() int { return 2 }
