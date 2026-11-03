package fmt;

import app.Packager;

public class Apk implements Packager {
    public String fileName(String target) { return target + ".Apk"; }
    public void pack(String target) { }
    public void pack(String target, int level) { }
}
