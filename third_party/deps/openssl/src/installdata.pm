package OpenSSL::safe::installdata;

use strict;
use warnings;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw($PREFIX
                  $BINDIR $BINDIR_REL
                  $LIBDIR $LIBDIR_REL
                  $INCLUDEDIR $INCLUDEDIR_REL
                  $APPLINKDIR $APPLINKDIR_REL
                  $ENGINESDIR $ENGINESDIR_REL
                  $MODULESDIR $MODULESDIR_REL
                  $PKGCONFIGDIR $PKGCONFIGDIR_REL
                  $CMAKECONFIGDIR $CMAKECONFIGDIR_REL
                  $VERSION @LDLIBS);

our $PREFIX             = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos';
our $BINDIR             = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/bin';
our $BINDIR_REL         = 'bin';
our $LIBDIR             = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/lib';
our $LIBDIR_REL         = 'lib';
our $INCLUDEDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/include';
our $INCLUDEDIR_REL     = 'include';
our $APPLINKDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/include/openssl';
our $APPLINKDIR_REL     = 'include/openssl';
our $ENGINESDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/lib/engines-3';
our $ENGINESDIR_REL     = 'lib/engines-3';
our $MODULESDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/lib/ossl-modules';
our $MODULESDIR_REL     = 'lib/ossl-modules';
our $PKGCONFIGDIR       = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/lib/pkgconfig';
our $PKGCONFIGDIR_REL   = 'lib/pkgconfig';
our $CMAKECONFIGDIR     = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/install-ohos/lib/cmake/OpenSSL';
our $CMAKECONFIGDIR_REL = 'lib/cmake/OpenSSL';
our $VERSION            = '3.3.1';
our @LDLIBS             =
    # Unix and Windows use space separation, VMS uses comma separation
    split(/ +| *, */, '-ldl -pthread ');

1;
