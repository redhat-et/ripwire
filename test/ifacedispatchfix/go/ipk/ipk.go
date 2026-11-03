package ipk

import (
	"io"

	"example.com/ifd/pkgr"
)

type Ipk struct{}

func (Ipk) ConventionalFileName(info *pkgr.Info) string {
	return info.Target + ".ipk"
}

func (Ipk) Package(info *pkgr.Info, w io.Writer) error {
	return nil
}
