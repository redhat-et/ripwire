package fmt;

import app.Packager;

public class Rpm implements Packager {
    public String fileName(String target) { return target + ".Rpm"; }
    public void pack(String target) { }
    public void pack(String target, int level) { }
}
