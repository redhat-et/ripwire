package cmd

import (
	"io"

	"example.com/ifd/pkgr"
)

func doPackage(info *pkgr.Info, w io.Writer) error {
	pkg, err := pkgr.Get("deb")
	if err != nil {
		return err
	}
	info.Target = pkg.ConventionalFileName(info)
	return pkg.Package(info, w)
}

func byParam(p pkgr.Packager, info *pkgr.Info) string {
	return p.ConventionalFileName(info)
}
