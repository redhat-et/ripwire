// C++ library: defines render(), which is called cross-language from app.py.
int render()
{
    return 42;
}

int cppMain()
{
    return render();   // same-language call → resolves cleanly (not unresolved)
}
