.class public Lcom/example/A;
.super Ljava/lang/Object;

# constructor and two methods; addTwo invokes addOne on this class.

.method public constructor <init>()V
    .registers 1
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method

.method public addOne(I)I
    .registers 2
    add-int/lit8 v0, p1, 0x1
    return v0
.end method

.method public addTwo(I)I
    .registers 2
    invoke-virtual {p0, p1}, Lcom/example/A; -> addOne(I)I
    move-result v0
    return v0
.end method
