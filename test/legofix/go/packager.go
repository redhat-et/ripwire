package nfpm

import "io"

// Info is the package metadata a Packager reads.
type Info struct {
	Name    string
	Version string
}

// Packager declares two methods in its own body (the goreleaser/nfpm shape, #404).
type Packager interface {
	Package(info *Info, w io.Writer) error
	ConventionalFileName(info *Info) string
}

// Deb implements both of Packager's methods; Go needs no clause naming the interface.
type Deb struct{}

func (d *Deb) Package(info *Info, w io.Writer) error {
	_, err := io.WriteString(w, info.Name)
	return err
}

func (d *Deb) ConventionalFileName(info *Info) string {
	return info.Name + "_" + info.Version + ".deb"
}

// SignedPackager only embeds Packager: its body declares no method of its own.
type SignedPackager interface {
	Packager
}

// Walker's one method takes an interface LITERAL: Pos belongs to the parameter's type, not to Walker.
type Walker interface {
	Walk(n interface{ Pos() int }) bool
}
