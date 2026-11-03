package fzt

import "testing"

func assertMatch(t *testing.T, fun func(string) int) {
	if fun("x") != 1 {
		t.Fail()
	}
}

func TestMatchV1(t *testing.T) { assertMatch(t, MatchV1) }
