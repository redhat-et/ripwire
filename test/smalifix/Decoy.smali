.class public Lcom/example/Decoy;
.super Ljava/lang/Object;

# same short method name as A.addOne; the edge from A.addTwo must not land here.

.method public addOne(I)I
    .registers 2
    return p1
.end method
