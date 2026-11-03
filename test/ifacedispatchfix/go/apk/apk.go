package apk

import (
	"io"

	"example.com/ifd/pkgr"
)

type Apk struct{}

func (Apk) ConventionalFileName(info *pkgr.Info) string {
	return info.Target + ".apk"
}

func (Apk) Package(info *pkgr.Info, w io.Writer) error {
	return nil
}
