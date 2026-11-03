package app;
@FunctionalInterface
public interface Hasher {
    int hash(String s);
    String toString();
    int hashCode();
}
