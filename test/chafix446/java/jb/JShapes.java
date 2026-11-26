package jb;
public class JShapes {
    public static class JSimple extends JBase implements JIface { public void act() {} }
    public static class JGeneric extends JBase<String> {}
    public static class JQual extends JShapes.JGeneric {}
    public static class JQualGen extends jb.JBase<String> {}
    public static class JEntry<K, V> implements JMap.Entry<K, V> { public K key() { return null; } }
    public static class JOuterNode {}
    public static class JHolder {
        public static class JOuterNode extends JShapes.JOuterNode {}
        public static class JKid extends JOuterNode {}
    }
    JIface anon = new JIface() { public void act() {} };
}
