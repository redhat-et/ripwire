package fzt

func MatchV1(text string) int { return len(text) }

func Score(text string) int { return MatchV1(text) + 1 }
