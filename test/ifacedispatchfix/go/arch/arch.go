package arch

import (
	"io"

	"example.com/ifd/pkgr"
)

type Arch struct{}

func (Arch) ConventionalFileName(info *pkgr.Info) string {
	return info.Target + ".arch"
}

func (Arch) Package(info *pkgr.Info, w io.Writer) error {
	return nil
}
