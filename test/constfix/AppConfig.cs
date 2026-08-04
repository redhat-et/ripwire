// C# settings class — const + static readonly SCREAMING_SNAKE constants.
public class AppConfig {
    public const int CS_MAX_RETRIES = 5;

    public static readonly string[] CS_DEFAULT_HOSTS = { "a.example", "b.example" };

    // property — stays a var def via the existing property_declaration pattern
    public int NotAConst { get; set; }

    public int Retries() {
        return CS_MAX_RETRIES;
    }
}
