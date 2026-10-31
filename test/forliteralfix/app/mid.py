import os

def ten_lines(cfg):
    a = os.environ.get('APPTOOL_TEN_FLAG')
    cfg.t0 = a  # ten 0
    cfg.t1 = a  # ten 1
    cfg.t2 = a  # ten 2
    cfg.t3 = a  # ten 3
    cfg.t4 = a  # ten 4
    cfg.t5 = a  # ten 5
    cfg.t6 = a  # ten 6
    return a


def eleven_lines(cfg):
    a = os.environ.get('APPTOOL_ELEVEN_FLAG')
    cfg.e0 = a  # eleven 0
    cfg.e1 = a  # eleven 1
    cfg.e2 = a  # eleven 2
    cfg.e3 = a  # eleven 3
    cfg.e4 = a  # eleven 4
    cfg.e5 = a  # eleven 5
    cfg.e6 = a  # eleven 6
    cfg.e7 = a  # eleven 7
    return a
