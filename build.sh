#!/bin/sh

# Copyright (c) 2024-2024 刘富频
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

# If IFS is not set, the default value will be <space><tab><newline>
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_05_03
unset IFS


COLOR_RED='\033[0;31m'          # Red
COLOR_GREEN='\033[0;32m'        # Green
COLOR_YELLOW='\033[0;33m'       # Yellow
COLOR_BLUE='\033[0;94m'         # Blue
COLOR_PURPLE='\033[0;35m'       # Purple
COLOR_OFF='\033[0m'             # Reset

print() {
    printf '%b' "$*"
}

echo() {
    printf '%b\n' "$*"
}

note() {
    printf '%b\n' "${COLOR_YELLOW}🔔  $*${COLOR_OFF}" >&2
}

warn() {
    printf '%b\n' "${COLOR_YELLOW}🔥  $*${COLOR_OFF}" >&2
}

success() {
    printf '%b\n' "${COLOR_GREEN}[✔] $*${COLOR_OFF}" >&2
}

error() {
    printf '%b\n' "${COLOR_RED}💔  $ARG0: $*${COLOR_OFF}" >&2
}

abort() {
    EXIT_STATUS_CODE="$1"
    shift
    printf '%b\n' "${COLOR_RED}💔  $ARG0: $*${COLOR_OFF}" >&2
    exit "$EXIT_STATUS_CODE"
}

run() {
    echo "${COLOR_PURPLE}==>${COLOR_OFF} ${COLOR_GREEN}$@${COLOR_OFF}"
    eval "$@"
}

isInteger() {
    case "${1#[+-]}" in
        (*[!0123456789]*) return 1 ;;
        ('')              return 1 ;;
        (*)               return 0 ;;
    esac
}

# wfetch <URL> [--uri=<URL-MIRROR>] [--sha256=<SHA256>] [-o <OUTPUT-PATH>] [--no-buffer]
#
# If -o <OUTPUT-PATH> option is unspecified, the result will be written to <PWD>/$(basename <URL>).
#
# If <OUTPUT-PATH> is . .. ./ ../ or ends with slash(/), then it will be treated as a directory, otherwise, it will be treated as a filepath.
#
# If <OUTPUT-PATH> is -, then it will be treated as /dev/stdout.
#
# If <OUTPUT-PATH> is treated as a directory, then it will be expanded to <OUTPUT-PATH>/$(basename <URL>)
#
wfetch() {
    unset FETCH_UTS
    unset FETCH_SHA

    unset FETCH_URL
    unset FETCH_URI

    unset FETCH_PATH

    unset FETCH_OUTPUT_DIR
    unset FETCH_OUTPUT_FILEPATH
    unset FETCH_OUTPUT_FILENAME

    unset FETCH_BUFFER_FILEPATH

    unset FETCH_SHA256_EXPECTED

    unset NOT_BUFFER

    [ -z "$1" ] && abort 1 "wfetch <URL> [OPTION]... , <URL> must be non-empty."

    if [ -z "$URL_TRANSFORM" ] ; then
        FETCH_URL="$1"
    else
        FETCH_URL="$("$URL_TRANSFORM" "$1")" || return 1
    fi

    shift

    while [ -n "$1" ]
    do
        case $1 in
            --uri=*)
                FETCH_URI="${1#*=}"
                ;;
            --sha256=*)
                FETCH_SHA256_EXPECTED="${1#*=}"
                ;;
            -o) shift
                if [ -z "$1" ] ; then
                    abort 1 "wfetch <URL> -o <PATH> , <PATH> must be non-empty."
                else
                    FETCH_PATH="$1"
                fi
                ;;
            --no-buffer)
                NOT_BUFFER=1
                ;;
            *)  abort 1 "wfetch <URL> [--uri=<URL-MIRROR>] [--sha256=<SHA256>] [-o <PATH>] [-q] , unrecognized option: $1"
        esac
        shift
    done

    if [ -z "$FETCH_URI" ] ; then
        # remove query params
        FETCH_URI="${FETCH_URL%%'?'*}"
        FETCH_URI="https://fossies.org/linux/misc/${FETCH_URI##*/}"
    else
        if [ -n "$URL_TRANSFORM" ] ; then
            FETCH_URI="$("$URL_TRANSFORM" "$FETCH_URI")" || return 1
        fi
    fi

    case $FETCH_PATH in
        -)  FETCH_BUFFER_FILEPATH='-' ;;
        .|'')
            FETCH_OUTPUT_DIR='.'
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        ..)
            FETCH_OUTPUT_DIR='..'
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        */)
            FETCH_OUTPUT_DIR="${FETCH_PATH%/}"
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        *)
            FETCH_OUTPUT_DIR="$(dirname "$FETCH_PATH")"
            FETCH_OUTPUT_FILEPATH="$FETCH_PATH"
    esac

    if [ -n "$FETCH_OUTPUT_FILEPATH" ] ; then
        if [ -f "$FETCH_OUTPUT_FILEPATH" ] ; then
            if [ -n "$FETCH_SHA256_EXPECTED" ] ; then
                if [ "$(sha256sum "$FETCH_OUTPUT_FILEPATH" | cut -d ' ' -f1)" = "$FETCH_SHA256_EXPECTED" ] ; then
                    success "$FETCH_OUTPUT_FILEPATH already have been fetched."
                    return 0
                fi
            fi
        fi

        if [ "$NOT_BUFFER" = 1 ] ; then
            FETCH_BUFFER_FILEPATH="$FETCH_OUTPUT_FILEPATH"
        else
            FETCH_UTS="$(date +%s)"

            FETCH_SHA="$(printf '%s\n' "$FETCH_URL:$$:$FETCH_UTS" | sha256sum | cut -d ' ' -f1)"

            FETCH_BUFFER_FILEPATH="$FETCH_OUTPUT_DIR/$FETCH_SHA.tmp"
        fi
    fi

    for FETCH_TOOL in curl wget http lynx aria2c axel
    do
        if command -v "$FETCH_TOOL" > /dev/null ; then
            break
        else
            unset FETCH_TOOL
        fi
    done

    if [ -z "$FETCH_TOOL" ] ; then
        abort 1 "no fetch tool found, please install one of curl wget http lynx aria2c axel, then try again."
    fi

    if [                -n "$FETCH_OUTPUT_DIR" ] ; then
        if [ !          -d "$FETCH_OUTPUT_DIR" ] ; then
            run install -d "$FETCH_OUTPUT_DIR" || return 1
        fi
    fi

    case $FETCH_TOOL in
        curl)
            CURL_OPTIONS="--fail --retry 20 --retry-delay 30 --location"

            if [ "$DUMP_HTTP" = 1 ] ; then
                CURL_OPTIONS="$CURL_OPTIONS --verbose"
            fi

            if [ -n "$SSL_CERT_FILE" ] ; then
                CURL_OPTIONS="$CURL_OPTIONS --cacert $SSL_CERT_FILE"
            fi

            run "curl $CURL_OPTIONS -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "curl $CURL_OPTIONS -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        wget)
            run "wget --timeout=60 -O '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "wget --timeout=60 -O '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        http)
            run "http --timeout=60 -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "http --timeout=60 -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        lynx)
            run "lynx -source '$FETCH_URL' > '$FETCH_BUFFER_FILEPATH'" ||
            run "lynx -source '$FETCH_URI' > '$FETCH_BUFFER_FILEPATH'"
            ;;
        aria2c)
            run "aria2c -d '$FETCH_OUTPUT_DIR' -o '$FETCH_OUTPUT_FILENAME' '$FETCH_URL'" ||
            run "aria2c -d '$FETCH_OUTPUT_DIR' -o '$FETCH_OUTPUT_FILENAME' '$FETCH_URI'"
            ;;
        axel)
            run "axel -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "axel -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        *)  abort 1 "wfetch() unimplementation: $FETCH_TOOL"
            ;;
    esac

    [ $? -eq 0 ] || return 1

    if [ -n "$FETCH_OUTPUT_FILEPATH" ] ; then
        if [ -n "$FETCH_SHA256_EXPECTED" ] ; then
            FETCH_SHA256_ACTUAL="$(sha256sum "$FETCH_BUFFER_FILEPATH" | cut -d ' ' -f1)"

            if [ "$FETCH_SHA256_ACTUAL" != "$FETCH_SHA256_EXPECTED" ] ; then
                abort 1 "sha256sum mismatch.\n    expect : $FETCH_SHA256_EXPECTED\n    actual : $FETCH_SHA256_ACTUAL\n"
            fi
        fi

        if [ "$NOT_BUFFER" != 1 ] ; then
            run mv "$FETCH_BUFFER_FILEPATH" "$FETCH_OUTPUT_FILEPATH"
        fi
    fi
}

filetype_from_url() {
    # remove query params
    URL="${1%%'?'*}"

    FNAME="${URL##*/}"

    case $FNAME in
        *.tar.gz|*.tgz)
            printf '%s\n' '.tgz'
            ;;
        *.tar.lz|*.tlz)
            printf '%s\n' '.tlz'
            ;;
        *.tar.xz|*.txz)
            printf '%s\n' '.txz'
            ;;
        *.tar.bz2|*.tbz2)
            printf '%s\n' '.tbz2'
            ;;
        *.*)printf '%s\n' ".${FNAME##*.}"
    esac
}

inspect_install_arguments() {
    unset PROFILE

    unset LOG_LEVEL

    unset BUILD_NJOBS

    unset ENABLE_LTO

    unset REQUEST_TO_KEEP_SESSION_DIR

    unset REQUEST_TO_EXPORT_COMPILE_COMMANDS_JSON

    unset SPECIFIED_PACKAGE_LIST

    unset SESSION_DIR
    unset DOWNLOAD_DIR
    unset PACKAGE_INSTALL_DIR

    unset DUMP_ENV
    unset DUMP_HTTP

    unset VERBOSE_GMAKE

    unset DEBUG_CC
    unset DEBUG_LD

    unset DEBUG_GMAKE

    while [ -n "$1" ]
    do
        case $1 in
            -x) set -x ;;
            -q) LOG_LEVEL=0 ;;
            -v) LOG_LEVEL=2

                DUMP_ENV=1
                DUMP_HTTP=1

                VERBOSE_GMAKE=1
                ;;
            -vv)LOG_LEVEL=3

                DUMP_ENV=1
                DUMP_HTTP=1

                VERBOSE_GMAKE=1

                DEBUG_CC=1
                DEBUG_LD=1

                DEBUG_GMAKE=1
                ;;
            -v-env)
                DUMP_ENV=1
                ;;
            -v-http)
                DUMP_HTTP=1
                ;;
            -v-gmake)
                VERBOSE_GMAKE=1
                ;;
            -v-cc)
                DEBUG_CC=1
                ;;
            -v-ld)
                DEBUG_LD=1
                ;;
            -x-gmake)
                DEBUG_GMAKE=1
                ;;
            --profile=*)
                PROFILE="${1#*=}"
                ;;
            --session-dir=*)
                SESSION_DIR="${1#*=}"

                case $SESSION_DIR in
                    /*) ;;
                    *)  SESSION_DIR="$PWD/$SESSION_DIR"
                esac
                ;;
            --download-dir=*)
                DOWNLOAD_DIR="${1#*=}"

                case $DOWNLOAD_DIR in
                    /*) ;;
                    *)  DOWNLOAD_DIR="$PWD/$DOWNLOAD_DIR"
                esac
                ;;
            --prefix=*)
                PACKAGE_INSTALL_DIR="${1#*=}"

                case $PACKAGE_INSTALL_DIR in
                    /*) ;;
                    *)  PACKAGE_INSTALL_DIR="$PWD/$PACKAGE_INSTALL_DIR"
                esac
                ;;
            -j) shift
                isInteger "$1" || abort 1 "-j <N>, <N> must be an integer."
                BUILD_NJOBS="$1"
                ;;
            -K) REQUEST_TO_KEEP_SESSION_DIR=1 ;;
            -E) REQUEST_TO_EXPORT_COMPILE_COMMANDS_JSON=1 ;;

            -*) abort 1 "unrecognized option: $1"
                ;;
            *)  SPECIFIED_PACKAGE_LIST="$SPECIFIED_PACKAGE_LIST $1"
        esac
        shift
    done

    #########################################################################################

    : ${PROFILE:=release}
    : ${ENABLE_LTO:=1}

    : ${SESSION_DIR:="$HOME/.xbuilder/run/$$"}
    : ${DOWNLOAD_DIR:="$HOME/.xbuilder/downloads"}
    : ${PACKAGE_INSTALL_DIR:="$HOME/.xbuilder/installed/ruby"}

    #########################################################################################

    AUX_INSTALL_DIR="$SESSION_DIR/auxroot"
    AUX_INCLUDE_DIR="$AUX_INSTALL_DIR/include"
    AUX_LIBRARY_DIR="$AUX_INSTALL_DIR/lib"

    #########################################################################################

    NATIVE_PLATFORM_KIND="$(uname -s | tr A-Z a-z)"
    NATIVE_PLATFORM_ARCH="$(uname -m)"

    #########################################################################################

    if [ -z "$BUILD_NJOBS" ] ; then
        if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
            NATIVE_PLATFORM_NCPU="$(sysctl -n machdep.cpu.thread_count)"
        else
            NATIVE_PLATFORM_NCPU="$(nproc)"
        fi

        BUILD_NJOBS="$NATIVE_PLATFORM_NCPU"
    fi

    #########################################################################################

    if [ "$LOG_LEVEL" = 0 ] ; then
        exec 1>/dev/null
        exec 2>&1
    else
        if [ -z "$LOG_LEVEL" ] ; then
            LOG_LEVEL=1
        fi
    fi

    #########################################################################################

    if [ -z "$GMAKE" ] ; then
        GMAKE="$(command -v gmake || command -v make)" || abort 1 "command not found: gmake"
    fi

    #########################################################################################

    unset CC_ARGS
    unset PP_ARGS
    unset LD_ARGS

    if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
        [ -z "$CC"      ] &&      CC="$(xcrun --sdk macosx --find clang)"
        [ -z "$CXX"     ] &&     CXX="$(xcrun --sdk macosx --find clang++)"
        [ -z "$AS"      ] &&      AS="$(xcrun --sdk macosx --find as)"
        [ -z "$LD"      ] &&      LD="$(xcrun --sdk macosx --find ld)"
        [ -z "$AR"      ] &&      AR="$(xcrun --sdk macosx --find ar)"
        [ -z "$RANLIB"  ] &&  RANLIB="$(xcrun --sdk macosx --find ranlib)"
        [ -z "$SYSROOT" ] && SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"

        [ -z "$MACOSX_DEPLOYMENT_TARGET" ] && MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion)"

        CC_ARGS="-isysroot $SYSROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -arch $NATIVE_PLATFORM_ARCH -Qunused-arguments"
        PP_ARGS="-isysroot $SYSROOT -Qunused-arguments"
        LD_ARGS="-isysroot $SYSROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -arch $NATIVE_PLATFORM_ARCH"
    else
        [ -z "$CC" ] && {
             CC="$(command -v cc  || command -v clang   || command -v gcc)" || abort 1 "C Compiler not found."
        }

        [ -z "$CXX" ] && {
            CXX="$(command -v c++ || command -v clang++ || command -v g++)" || abort 1 "C++ Compiler not found."
        }

        [ -z "$AS" ] && {
            AS="$(command -v as)" || abort 1 "command not found: as"
        }

        [ -z "$LD" ] && {
            LD="$(command -v ld)" || abort 1 "command not found: ld"
        }

        [ -z "$AR" ] && {
            AR="$(command -v ar)" || abort 1 "command not found: ar"
        }

        [ -z "$RANLIB" ] && {
            RANLIB="$(command -v ranlib)" || abort 1 "command not found: ranlib"
        }

        CC_ARGS="-fPIC -fno-common"

        # https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html
        LD_ARGS="-Wl,--as-needed -Wl,-z,muldefs -Wl,--allow-multiple-definition"
    fi

    #########################################################################################

    CPP="$CC -E"

    #########################################################################################

    [ "$DEBUG_CC" = 1 ] && CC_ARGS="$CC_ARGS -v"
    [ "$DEBUG_LD" = 1 ] && LD_ARGS="$LD_ARGS -Wl,-v"

    case $PROFILE in
        debug)
            CC_ARGS="$CC_ARGS -O0 -g"
            ;;
        release)
            CC_ARGS="$CC_ARGS -Os"

            if [ "$ENABLE_LTO" = 1 ] ; then
                LD_ARGS="$LD_ARGS -flto"
            fi

            if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
                LD_ARGS="$LD_ARGS -Wl,-S"
            else
                LD_ARGS="$LD_ARGS -Wl,-s"
            fi
    esac

    case $NATIVE_PLATFORM_KIND in
         netbsd) LD_ARGS="$LD_ARGS -lpthread" ;;
        openbsd) LD_ARGS="$LD_ARGS -lpthread" ;;
    esac

    #########################################################################################

    PP_ARGS="$PP_ARGS -I$AUX_INCLUDE_DIR"
    LD_ARGS="$LD_ARGS -L$AUX_LIBRARY_DIR"

    PATH="$AUX_INSTALL_DIR/bin:$PATH"

    #########################################################################################

      CFLAGS="$CC_ARGS   $CFLAGS"
    CXXFLAGS="$CC_ARGS $CXXFLAGS"
    CPPFLAGS="$PP_ARGS $CPPFLAGS"
     LDFLAGS="$LD_ARGS  $LDFLAGS"

    #########################################################################################

    for TOOL in CC CXX CPP AS AR RANLIB LD SYSROOT CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
    do
        export "${TOOL}"
    done

    #########################################################################################

    unset PKG_CONFIG_LIBDIR
    unset PKG_CONFIG_PATH
    unset PKG_CONFIG
    unset ACLOCAL_PATH

    unset LIBS

    # autoreconf --help

    unset AUTOCONF
    unset AUTOHEADER
    unset AUTOM4TE
    unset AUTOMAKE
    unset AUTOPOINT
    unset ACLOCAL
    unset GTKDOCIZE
    unset INTLTOOLIZE
    unset LIBTOOLIZE
    unset M4
    unset MAKE

    # https://stackoverflow.com/questions/18476490/what-is-purpose-of-target-arch-variable-in-makefiles
    unset TARGET_ARCH

    # https://keith.github.io/xcode-man-pages/xcrun.1.html
    unset SDKROOT
}

configure() {
    for FILENAME in config.sub config.guess
    do
        FILEPATH="$SESSION_DIR/$FILENAME"

        [ -f "$FILEPATH" ] || {
            wfetch "https://git.savannah.gnu.org/cgit/config.git/plain/$FILENAME" -o "$FILEPATH"

            run chmod a+x "$FILEPATH"

            if [ "$FILENAME" = 'config.sub' ] ; then
                sed -i.bak 's/arm64-*/arm64-*|arm64e-*/g' "$FILEPATH"
            fi
        }

        find . -name "$FILENAME" -exec cp -vf "$FILEPATH" {} \;
    done

    run ./configure "--prefix=$PACKAGE_INSTALL_DIR" "$@"
    run "$GMAKE" "--jobs=$BUILD_NJOBS" V=1
    run "$GMAKE" install
}

install_the_given_package() {
    [ -z "$1" ] && abort 1 "install_the_given_package <PACKAGE-NAME> , <PACKAGE-NAME> is unspecified."

    unset PACKAGE_SRC_URL
    unset PACKAGE_SRC_URI
    unset PACKAGE_SRC_SHA
    unset PACKAGE_DEP_PKG
    unset PACKAGE_DOPATCH
    unset PACKAGE_INSTALL
    unset PACKAGE_DOTWEAK

    package_info_$1

    #########################################################################################

    for PACKAGE_DEPENDENCY in $PACKAGE_DEP_PKG
    do
        (install_the_given_package "$PACKAGE_DEPENDENCY")
    done

    #########################################################################################

    printf '\n%b\n' "${COLOR_PURPLE}=>> $ARG0: install package : $1${COLOR_OFF}"

    #########################################################################################

    if [ "$1" != ruby ] ; then
        PACKAGE_INSTALL_DIR="$AUX_INSTALL_DIR"
    fi

    #########################################################################################

    if [ -f "$PACKAGE_INSTALL_DIR/$1.yml" ] ; then
        note "package '$1' already has been installed, skipped."
        return 0
    fi

    #########################################################################################

    PACKAGE_SRC_FILETYPE="$(filetype_from_url "$PACKAGE_SRC_URL")"
    PACKAGE_SRC_FILENAME="$PACKAGE_SRC_SHA$PACKAGE_SRC_FILETYPE"
    PACKAGE_SRC_FILEPATH="$DOWNLOAD_DIR/$PACKAGE_SRC_FILENAME"

    #########################################################################################

    wfetch "$PACKAGE_SRC_URL" --uri="$PACKAGE_SRC_URI" --sha256="$PACKAGE_SRC_SHA" -o "$PACKAGE_SRC_FILEPATH"

    #########################################################################################

    PACKAGE_WORKING_DIR="$SESSION_DIR/$1"

    #########################################################################################

    run install -d "$PACKAGE_WORKING_DIR/src"
    run cd         "$PACKAGE_WORKING_DIR/src"

    #########################################################################################

    if [ -z "$TAR" ] ; then
        TAR="$(command -v bsdtar || command -v gtar || command -v tar)" || abort 1 "none of bsdtar, gtar, tar command was found."
    fi

    run "$TAR" xf "$PACKAGE_SRC_FILEPATH" --strip-components=1 --no-same-owner

    #########################################################################################

    if [ -n  "$PACKAGE_DOPATCH" ] ; then
        eval "$PACKAGE_DOPATCH"
    fi

    #########################################################################################

    if [ "$DUMP_ENV" = 1 ] ; then
        run export -p
    fi

    #########################################################################################

    if [ -n  "$PACKAGE_INSTALL" ] ; then
        eval "$PACKAGE_INSTALL"
    else
        abort 1 "PACKAGE_INSTALL variable is not set for package '$1'"
    fi

    #########################################################################################

    run cd "$PACKAGE_INSTALL_DIR"

    #########################################################################################

    if [ -n  "$PACKAGE_DOTWEAK" ] ; then
        eval "$PACKAGE_DOTWEAK"
    fi

    #########################################################################################

    run cd "$PACKAGE_INSTALL_DIR"

    #########################################################################################

    PACKAGE_INSTALL_UTS="$(date +%s)"

    cat > "$1.yml" <<EOF
src-url: $PACKAGE_SRC_URL
src-uri: $PACKAGE_SRC_URI
src-sha: $PACKAGE_SRC_SHA
dep-pkg: $PACKAGE_DEP_PKG
install: $PACKAGE_INSTALL
builtat: $PACKAGE_INSTALL_UTS
EOF

    cat > toolchain.txt <<EOF
     CC='$CC'
    CXX='$CXX'
     AS='$AS'
     LD='$LD'
     AR='$AR'
 RANLIB='$RANLIB'
SYSROOT='$SYSROOT'
PROFILE='$PROFILE'
 CFLAGS='$CFLAGS'
LDFLAGS='$LDFLAGS'
EOF
}

package_info_libz() {
    PACKAGE_SRC_URL='https://zlib.net/fossils/zlib-1.3.1.tar.gz'
    PACKAGE_SRC_SHA='9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23'
    PACKAGE_INSTALL='configure --static'
}

package_info_libffi() {
    PACKAGE_SRC_URL='https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz'
    PACKAGE_SRC_SHA='b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --disable-docs --disable-symvers'
}

package_info_libyaml() {
    PACKAGE_SRC_URL='https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz'
    PACKAGE_SRC_SHA='c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --enable-largefile'
}

package_info_libopenssl() {
    PACKAGE_SRC_URL='https://www.openssl.org/source/openssl-3.3.1.tar.gz'
    PACKAGE_SRC_SHA='777cd596284c883375a2a7a11bf5d2786fc5413255efab20c50d6ffe6d020b7e'
    PACKAGE_DEP_PKG='perl'
    PACKAGE_INSTALL='run ./config "--prefix=$PACKAGE_INSTALL_DIR" no-shared no-tests no-ssl3 no-ssl3-method no-zlib --libdir=lib --openssldir=etc/ssl && run "$GMAKE" build_libs "--jobs=$BUILD_NJOBS" && run "$GMAKE" install_dev'
    # https://github.com/openssl/openssl/blob/master/INSTALL.md
}

package_info_libxcrypt() {
    PACKAGE_SRC_URL='https://github.com/besser82/libxcrypt/releases/download/v4.4.36/libxcrypt-4.4.36.tar.xz'
    PACKAGE_SRC_SHA='e5e1f4caee0a01de2aee26e3138807d6d3ca2b8e67287966d1fefd65e1fd8943'
    PACKAGE_DEP_PKG='perl'
    PACKAGE_DOPATCH='export LDFLAGS="-static $LDFLAGS"'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-obsolete-api=glibc --disable-xcrypt-compat-files --disable-failure-tokens --disable-valgrind'
}

package_info_perl() {
    PACKAGE_SRC_URL='https://cpan.metacpan.org/authors/id/P/PE/PEVANS/perl-5.38.2.tar.xz'
    PACKAGE_SRC_URI='https://distfiles.macports.org/perl5.38/perl-5.38.2.tar.xz'
    PACKAGE_SRC_SHA='d91115e90b896520e83d4de6b52f8254ef2b70a8d545ffab33200ea9f1cf29e8'
    PACKAGE_INSTALL='run ./Configure "-Dprefix=$PACKAGE_INSTALL_DIR" -Dman1dir=none -Dman3dir=none -des -Dmake=gmake -Duselargefiles -Duseshrplib -Dusethreads -Dusenm=false -Dusedl=true && run "$GMAKE" "--jobs=$BUILD_NJOBS" && run "$GMAKE" install'
}

package_info_ruby() {
    PACKAGE_SRC_URL='https://cache.ruby-lang.org/pub/ruby/3.3/ruby-3.3.6.tar.gz'
    PACKAGE_SRC_SHA='8dc48fffaf270f86f1019053f28e51e4da4cce32a36760a0603a9aee67d7fd8d'
    PACKAGE_DEP_PKG='libz libyaml libffi libopenssl'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --disable-install-doc --disable-install-rdoc --disable-rpath --enable-load-relative --with-static-linked-ext --without-gmp --with-opt-dir="$AUX_INSTALL_DIR"'

    if [ "$NATIVE_PLATFORM_KIND" = linux ] ; then
        PACKAGE_DEP_PKG="$PACKAGE_DEP_PKG libxcrypt"
    fi

    PACKAGE_DOPATCH='
if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
cat > cc-wrapper <<EOF
#!/bin/sh

if [ "\$1" = -dynamic ] && [ "\$2" = -bundle ] ; then
    exec "$CC" "\$@" "$PACKAGE_WORKING_DIR/src/libruby.3.3-static.a" -framework CoreFoundation
else
    exec "$CC" "\$@"
fi
EOF
chmod +x cc-wrapper
export CC="$PWD/cc-wrapper"
fi
'
    PACKAGE_DOTWEAK='gsed -i "/^prefix=/c prefix=\${pcfiledir}/../.." lib/pkgconfig/*.pc'
}

package_info_gsed() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/sed/sed-4.9.tar.xz'
    PACKAGE_SRC_SHA='6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181'
    PACKAGE_INSTALL='configure --program-prefix=g --with-included-regex --without-selinux --disable-acl --disable-assert'
}


help() {
    printf '%b\n' "\
${COLOR_GREEN}A self-contained and relocatable Ruby distribution builder.${COLOR_OFF}

${COLOR_GREEN}$ARG0 --help${COLOR_OFF}
${COLOR_GREEN}$ARG0 -h${COLOR_OFF}
    show help of this command.

${COLOR_GREEN}$ARG0 config${COLOR_OFF}
    show config.

${COLOR_GREEN}$ARG0 install [OPTIONS]${COLOR_OFF}
    install ruby.

    Influential environment variables: TAR, GMAKE, CC, CXX, AS, LD, AR, RANLIB, CFLAGS, CXXFLAGS, CPPFLAGS, LDFLAGS

    OPTIONS:
        ${COLOR_BLUE}--prefix=<DIR>${COLOR_OFF}
            specify where to be installed into.

        ${COLOR_BLUE}--session-dir=<DIR>${COLOR_OFF}
            specify the session directory.

        ${COLOR_BLUE}--download-dir=<DIR>${COLOR_OFF}
            specify the download directory.

        ${COLOR_BLUE}--profile=<debug|release>${COLOR_OFF}
            specify the build profile.

            debug:
                  CFLAGS: -O0 -g
                CXXFLAGS: -O0 -g

            release:
                  CFLAGS: -Os
                CXXFLAGS: -Os
                CPPFLAGS: -DNDEBUG
                 LDFLAGS: -flto -Wl,-s

        ${COLOR_BLUE}-j <N>${COLOR_OFF}
            specify the number of jobs you can run in parallel.

        ${COLOR_BLUE}-E${COLOR_OFF}
            export compile_commands.json

        ${COLOR_BLUE}-K${COLOR_OFF}
            keep the session directory even if this packages are successfully installed.

        ${COLOR_BLUE}-x${COLOR_OFF}
            debug current running shell.

        ${COLOR_BLUE}-q${COLOR_OFF}
            silent mode. no any messages will be output to terminal.

        ${COLOR_BLUE}-v${COLOR_OFF}
            verbose mode. many messages will be output to terminal.

            This option is equivalent to -v-* options all are supplied.

        ${COLOR_BLUE}-vv${COLOR_OFF}
            very verbose mode. many many messages will be output to terminal.

            This option is equivalent to -v-* options all are supplied.

        ${COLOR_BLUE}-v-env${COLOR_OFF}
            show all environment variables before starting to build.

        ${COLOR_BLUE}-v-http${COLOR_OFF}
            show http request/response.

        ${COLOR_BLUE}-v-gmake${COLOR_OFF}
            pass V=1 argument to gmake command.

        ${COLOR_BLUE}-v-cc${COLOR_OFF}
            pass -v argument to the C/C++ compiler.

        ${COLOR_BLUE}-v-ld${COLOR_OFF}
            pass -v argument to the linker.

        ${COLOR_BLUE}-x-gmake${COLOR_OFF}
            pass --debug argument to gmake command.
"
}

show_config() {
    unset PACKAGE_SRC_URL
    unset PACKAGE_SRC_URI
    unset PACKAGE_SRC_SHA
    unset PACKAGE_DEP_PKG
    unset PACKAGE_DOPATCH
    unset PACKAGE_INSTALL
    unset PACKAGE_DOTWEAK

    package_info_$1

    cat <<EOF
$1:
    src-url: $PACKAGE_SRC_URL
    src-sha: $PACKAGE_SRC_SHA

EOF

    for DEP_PKG_NAME in $PACKAGE_DEP_PKG
    do
        (show_config "$DEP_PKG_NAME")
    done
}

ARG0="$0"

case $1 in
    ''|--help|-h)
        help
        ;;
    config)
        show_config ruby
        ;;
    install)
        shift

        inspect_install_arguments "$@"

        (install_the_given_package gsed)
         install_the_given_package ruby

        if [ "$REQUEST_TO_KEEP_SESSION_DIR" != 1 ] ; then
            rm -rf "$SESSION_DIR"
        fi
        ;;
    *)  abort 1 "unrecognized argument: $1"
esac
