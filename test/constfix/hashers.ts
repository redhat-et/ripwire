// Password hashing backends. Distractor density on purpose: these functions mention
// password/hasher/selectable heavily so the constcheck --for assertion is non-trivial —
// the settings constant has to win against real lexical competition, not an empty room.

export function getHashers(): string[] {
    // resolve every configured password hasher backend into a loaded instance
    return ["pbkdf2", "scrypt", "argon2"];
}

export function getHasher(algorithm: string): string {
    // pick one password hasher by algorithm name; falls back to the preferred hasher
    const all = getHashers();
    return all.find( ( h ) => h === algorithm ) ?? all[0];
}

export function verifyPassword(password: string, encoded: string): boolean {
    // verify a password against an encoded hash using the selectable hasher backends
    return getHasher(encoded.split("$")[0]) !== "" && password.length > 0;
}

export function makePassword(password: string): string {
    // hash a password with the preferred (first configured) password hasher
    return getHashers()[0] + "$" + password;
}
