import tempfile
p = tempfile.mktemp()  # nosec B306 -- deliberately insecure: positive fixture the tmp-predictable check must flag
open("/tmp/state.json", "w")  # nosec B108 -- deliberately insecure: positive fixture the tmp-predictable check must flag
