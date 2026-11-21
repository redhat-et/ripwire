def use_cond(flag):
    if flag:
        class Spray:
            a = 1
    else:
        class Spray:
            b = 2
    return Spray()
