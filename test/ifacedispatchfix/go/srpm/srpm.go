package srpm

import (
	"io"

	"example.com/ifd/pkgr"
)

type Srpm struct{}

func (Srpm) ConventionalFileName(info *pkgr.Info) string {
	return info.Target + ".srpm"
}

func (Srpm) Package(info *pkgr.Info, w io.Writer) error {
	return nil
}
