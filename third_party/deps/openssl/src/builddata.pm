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

our $PREFIX             = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src';
our $BINDIR             = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src/apps';
our $BINDIR_REL         = 'apps';
our $LIBDIR             = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src';
our $LIBDIR_REL         = '.';
our $INCLUDEDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src/include';
our $INCLUDEDIR_REL     = 'include';
our $APPLINKDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src/ms';
our $APPLINKDIR_REL     = 'ms';
our $ENGINESDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src/engines';
our $ENGINESDIR_REL     = 'engines';
our $MODULESDIR         = '/Users/caidingding233/projects/qemu-hmos/third_party/deps/openssl/src/providers';
our $MODULESDIR_REL     = 'providers';
our $PKGCONFIGDIR       = '';
our $PKGCONFIGDIR_REL   = '';
our $CMAKECONFIGDIR     = '';
our $CMAKECONFIGDIR_REL = '';
our $VERSION            = '3.3.1';
our @LDLIBS             =
    # Unix and Windows use space separation, VMS uses comma separation
    split(/ +| *, */, '-ldl -pthread ');

1;
