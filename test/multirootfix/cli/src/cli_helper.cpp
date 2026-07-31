// cli_helper.cpp — cli's OWN same_name_helper (the in-root target the bare call in cli_main.cpp must
// keep resolving to, exactly as in a solo run — combining roots must not add ambiguity or steal the edge).
int same_name_helper()
{
    return 2;
}
