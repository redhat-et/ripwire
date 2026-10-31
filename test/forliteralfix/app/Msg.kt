fun failKt(x: Int) {
    if (x > 0) {
        throw IllegalStateException(
            """bad things happened here"""
        )
    }
}
