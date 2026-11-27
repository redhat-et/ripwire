struct Ledger {
    int PostEntry(int e) { return e; }
};

int ProvenHop(Ledger& led) { return led.PostEntry(1); }

template <typename T> int NameHop(T& x) { return x.PostEntry(2); }

struct Svc {
    int Relay(Ledger& led) { return led.PostEntry(3); }
};

int OnlyByName() {
    Ledger l;
    return NameHop(l);
}

int BothPaths() {
    Ledger l;
    return ProvenHop(l) + NameHop(l);
}

template <typename S> int ByNameEdge(S& s) {
    Ledger l;
    return s.Relay(l);
}
