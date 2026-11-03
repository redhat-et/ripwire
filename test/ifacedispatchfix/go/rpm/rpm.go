package rpm

import (
	"io"

	"example.com/ifd/pkgr"
)

type Rpm struct{}

func (Rpm) ConventionalFileName(info *pkgr.Info) string {
	return info.Target + ".rpm"
}

func (Rpm) Package(info *pkgr.Info, w io.Writer) error {
	return nil
}
