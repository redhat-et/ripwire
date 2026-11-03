package fmt;

import app.Packager;

public class Deb implements Packager {
    public String fileName(String target) { return target + ".Deb"; }
    public void pack(String target) { }
    public void pack(String target, int level) { }
}
