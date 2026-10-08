package fzf

import "go.uber.org/zap"

// Service logs through an outside logger held in a field named like the in-repo log package.
type Service struct {
	log *zap.SugaredLogger
}

// Fail: s.log is a field of an outside type, never the in-repo log package.
func (s *Service) Fail(msg string) {
	s.log.Errorf("failed: %s", msg)
}

// Report: a local named log shadows nothing in-repo here; this file never imports the log package.
func Report(l *zap.SugaredLogger) {
	log := l
	log.Errorf("report")
}
