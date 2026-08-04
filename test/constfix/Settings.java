// Java settings class — static final SCREAMING_SNAKE constants.
public class Settings {
    public static final int JV_MAX_POOL_SIZE = 32;

    // camelCase instance field — must stay unindexed (fields are deliberately noise)
    private int javaCounter = 1;

    public int poolSize() {
        return JV_MAX_POOL_SIZE + javaCounter;
    }
}
