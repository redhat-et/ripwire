package deb

import (
	"io"

	"example.com/ifd/pkgr"
)

type Deb struct{}

func (Deb) ConventionalFileName(info *pkgr.Info) string {
	return info.Target + ".deb"
}

func (Deb) Package(info *pkgr.Info, w io.Writer) error {
	return nil
}
