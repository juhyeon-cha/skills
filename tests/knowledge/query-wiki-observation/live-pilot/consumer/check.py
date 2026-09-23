from app import consume
assert consume({"total": 1}) == 1
try:
    consume({})
except KeyError:
    pass
else:
    raise AssertionError("missing total must fail")
