import sys
import gdb

# Update module path.
dir_ = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/share/glib-2.0/gdb'
if not dir_ in sys.path:
    sys.path.insert(0, dir_)

from glib_gdb import register
register (gdb.current_objfile ())
