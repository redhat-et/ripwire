// Global auth settings for the app — the selectable password hashing backends.
// The first entry is the preferred algorithm; the rest are supported for upgrade.
export const TS_PASSWORD_HASHERS = [
    "app.auth.hashers.Pbkdf2Hasher",
    "app.auth.hashers.ScryptHasher",
    "app.auth.hashers.Argon2Hasher",
];

// Feature flags: which optional subsystems are enabled in this deployment.
export const TS_FEATURE_FLAGS = { newCheckout: true, betaSearch: false };

const TS_MAX_RETRIES = 5;

// lowercase top-level const — NOT a settings constant, must stay unindexed
const retryBudget = 3;

// SCREAMING_SNAKE arrow-function const — must stay a FUNCTION def, not become a var
export const TS_MAKE_HANDLER = () => ({ ok: true });

export function loadSettings(): number {
    // function-local SCREAMING_SNAKE — module-level patterns must not reach in here
    const TS_LOCAL_GUARD = 1;
    return TS_LOCAL_GUARD + TS_MAX_RETRIES;
}
