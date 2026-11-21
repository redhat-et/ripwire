def use_condassign(flag, other):
    if flag:
        class Spray:
            a = 1
    else:
        Spray = other
    return Spray()
