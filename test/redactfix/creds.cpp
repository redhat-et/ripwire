// creds.cpp — redaction gate fixture. Every credential below is a CLEARLY FAKE, well-known EXAMPLE
// value (AWS's own docs use AKIAIOSFODNN7EXAMPLE). ripwire must redact each true-positive when it
// emits this file's body (--pack-top-n / --expand), and must leave the decoys at the bottom intact.

#include <string>

// loadAwsKey — holds a fake AWS access-key id (AKIA + 16 upper-alnum). Must be redacted.
std::string loadAwsKey()
{
    // AWS access key id (the canonical AWS-docs example)
    return "AKIAIOSFODNN7EXAMPLE";
}

// loadAwsSecret — a 40-char base64-ish AWS secret ON a keyword-named line → keyword-gated redaction.
std::string loadAwsSecret()
{
    const char* aws_secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    return aws_secret_access_key;
}

// loadGitHubToken — a fake fine-grained GitHub PAT (ghp_ + 20+ token chars). Must be redacted.
std::string loadGitHubToken()
{
    return "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
}

// loadGitHubPat — the github_pat_ classic prefix form. Must be redacted.
std::string loadGitHubPat()
{
    return "github_pat_11ABCDEFG0abcdefghijklmnop";
}

// loadSlackToken — xoxb- Slack bot token shape. Must be redacted.
std::string loadSlackToken()
{
    return "xoxb-2401234567-1234567890123-fakeFAKEfakeFAKEfake0";
}

// loadGoogleApiKey — AIza + 35 chars, Google's fixed key shape. Must be redacted.
std::string loadGoogleApiKey()
{
    return "AIzaSyA1234567890abcdefghijklmnopqrstuvw";
}

// loadOpenAiKey — sk- + long token, OpenAI key shape. Must be redacted.
std::string loadOpenAiKey()
{
    return "sk-abcdef1234567890ABCDEFGHIJKLMNOPQRSTUV";
}

// loadAnthropicKey — sk-ant- prefix (Anthropic). Must be redacted (labelled anthropic-key).
std::string loadAnthropicKey()
{
    return "sk-ant-api03-abcdefGHIJKL1234567890mnopQRST";
}

// loadPrivateKey — a PEM private-key header. The BEGIN banner must be redacted.
std::string loadPrivateKey()
{
    return "-----BEGIN RSA PRIVATE KEY-----\nMIIEptfakebase64...\n-----END RSA PRIVATE KEY-----";
}

// loadGenericSecret — a 32+ char hex/base64 blob ON a credential-named assignment line → gated redaction.
std::string loadGenericSecret()
{
    const char* api_key = "0123456789abcdef0123456789abcdef0123";
    return api_key;
}

// loadAuthorizationHeader — an "Authorization: Bearer <jwt>" header line (A4-F11). "auth" alone is a
// substring of "authorization" and fails the old ':'/'=' gate right after the keyword; this must
// still be redacted via the standalone JWT rule (self-anchored, no keyword gate needed at all).
std::string loadAuthorizationHeader()
{
    const char* header = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U";
    return header;
}

// loadBareJwt — a bare eyJ… three-segment JWT with NO surrounding keyword at all. Must be redacted by
// the standalone JWT shape rule.
std::string loadBareJwt()
{
    return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U";
}

// ─── DECOYS: these are NOT secrets and MUST survive verbatim (precision-over-recall guarantee) ───

// decoyBearerProse — "bearer" used as an ordinary English word, no token follows. Must stay intact
// (the loose bearer/authorization gate only ENABLES the generic-secret scan on the line; there is no
// 32+ char credential-shaped run here, so nothing fires — precision preserved).
std::string decoyBearerProse()
{
    // the bearer of good news arrived early this morning with the quarterly report
    return "the bearer of good news arrived early this morning with the quarterly report";
}

// decoyGitSha — a 40-hex git commit SHA in prose, NO credential keyword on the line. Must stay intact.
std::string decoyGitSha()
{
    // pinned to commit da39a3ee5e6b4b0d3255bfef95601890afd80709 in the changelog
    return "da39a3ee5e6b4b0d3255bfef95601890afd80709";
}

// decoyBase64Vector — a base64 test vector with NO credential keyword on the line. Must stay intact.
std::string decoyBase64Vector()
{
    return "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsuICBhYmNkZWY";
}

// decoyShortSkIdent — an sk- prefixed identifier SHORTER than the 20-char threshold. Must stay intact.
std::string decoyShortSkIdent()
{
    const char* sk_local = "sk-test-123";
    return sk_local;
}
