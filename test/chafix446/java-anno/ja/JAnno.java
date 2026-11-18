package ja;
import java.lang.annotation.ElementType;
import java.lang.annotation.Target;
@Target(ElementType.TYPE_USE) @interface JMark {}
class JABase<T> {}
interface JAIface {}
class JAKid extends @JMark JABase {}
class JAGen extends @JMark JABase<String> {}
class JAPlain extends JABase {}
class JAImpl implements @JMark JAIface {}
