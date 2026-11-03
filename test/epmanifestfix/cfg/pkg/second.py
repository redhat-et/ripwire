def reload_reports(ep):
    if "x.report" == ep.group:
        return ep.load()
    return None
