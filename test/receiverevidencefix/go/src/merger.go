package fzf

// Merger has Get and Length too; an item's text field is never a Merger.
type Merger struct {
	lists [][]int
	count int
}

func (mg *Merger) Get(idx int) int {
	return mg.lists[0][idx]
}

func (mg *Merger) Length() int {
	return mg.count
}

func (mg *Merger) First() int {
	return mg.Get(0)
}
