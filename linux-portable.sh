#!/bin/sh

set -e


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
    printf '%b\n' "${COLOR_RED}💔  $*${COLOR_OFF}" >&2
}

abort() {
    EXIT_STATUS_CODE="$1"
    shift
    printf '%b\n' "${COLOR_RED}💔  $*${COLOR_OFF}" >&2
    exit "$EXIT_STATUS_CODE"
}

run() {
    echo "${COLOR_PURPLE}==>${COLOR_OFF} ${COLOR_GREEN}$@${COLOR_OFF}"
    eval "$@"
}


check_DT_NEEDED() {
    NEEDED_SHARED_LIBRARY_FILENAMEs="$(patchelf --print-needed "$1")"

    for NEEDED_SHARED_LIBRARY_FILENAME in $NEEDED_SHARED_LIBRARY_FILENAMEs
    do
        NEEDED_SHARED_LIBRARY_FILEPATH=

        case $1 in
            ./*)
                if [ -d lib ] ; then
                    NEEDED_SHARED_LIBRARY_FILEPATH="./lib/$NEEDED_SHARED_LIBRARY_FILENAME"

                    [ -f "$NEEDED_SHARED_LIBRARY_FILEPATH" ] || {
                        unset NEEDED_SHARED_LIBRARY_FILEPATH
                        NEEDED_SHARED_LIBRARY_FILEPATH="$(find ./lib \( -type f -or -type l \) -name "$NEEDED_SHARED_LIBRARY_FILENAME" -print -quit)"
                    }

                    [ -n "$NEEDED_SHARED_LIBRARY_FILEPATH" ] && {
                        FILEPATH_RPATH_MAP="$FILEPATH_RPATH_MAP
$1|${NEEDED_SHARED_LIBRARY_FILEPATH%/*}"
                    }
                fi
        esac

        #####################################################

        if [ -z "$NEEDED_SHARED_LIBRARY_FILEPATH" ] ; then
            NEEDED_SHARED_LIBRARY_FILEPATH="$(gcc -print-file-name="$NEEDED_SHARED_LIBRARY_FILENAME")"
            NEEDED_SYSTEM_SHARED_LIBS="$NEEDED_SYSTEM_SHARED_LIBS
$NEEDED_SHARED_LIBRARY_FILEPATH"
        fi

        check_DT_NEEDED "$NEEDED_SHARED_LIBRARY_FILEPATH"
    done
}

gen_c_source_file() {
    cat > "$1.c" <<EOF
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <linux/limits.h>

int main(int argc, char* argv[]) {
    char selfExecPath[PATH_MAX];

    int ret = readlink("/proc/self/exe", selfExecPath, PATH_MAX);

    if (ret == -1) {
        perror("/proc/self/exe");
        return 1;
    }

    selfExecPath[ret] = '\\0';

    ////////////////////////////////////////////////////

    int slashIndex = -1;

    char realExePath[ret + 5];

    for (int i = 0; i < ret; i++) {
        realExePath[i] = selfExecPath[i];

        if (selfExecPath[i] == '/') {
            slashIndex = i;
        }
    }

    realExePath[ret    ] = '.';
    realExePath[ret + 1] = 'b';
    realExePath[ret + 2] = 'i';
    realExePath[ret + 3] = 'n';
    realExePath[ret + 4] = '\\0';

    ////////////////////////////////////////////////////

    const char * dynamicLoaderName = "$2";
    const char * libraryPathRelativeToSelfExePath = "/$3";

    ////////////////////////////////////////////////////

    char libraryPath[PATH_MAX];

    for (int i = 0; i <= slashIndex; i++) {
        libraryPath[i] = selfExecPath[i];
    }

    for (int i = 1; ; i++) {
        libraryPath[slashIndex + i] = libraryPathRelativeToSelfExePath[i];

        if (libraryPathRelativeToSelfExePath[i] == '\\0') {
            break;
        }
    }

    ////////////////////////////////////////////////////

    char dynamicLoaderPath[PATH_MAX];

    ret = snprintf(dynamicLoaderPath, PATH_MAX, "%s/%s", libraryPath, dynamicLoaderName);

    if (ret < 0) {
        perror(NULL);
        return 2;
    }

    ////////////////////////////////////////////////////

    char* argv2[argc + 6];

    argv2[0] = dynamicLoaderPath;
    argv2[1] = (char*)"--library-path";
    argv2[2] = libraryPath;
    argv2[3] = (char*)"--argv0";
    argv2[4] = selfExecPath;
    argv2[5] = realExePath;

    for (int i = 1; i < argc; i++) {
        argv2[i + 5] = argv[i];
    }

    argv2[argc + 5] = NULL;

    execv (dynamicLoaderPath, argv2);
    perror(dynamicLoaderPath);
    return 255;
}
EOF
}

##################################################################

[ -n "$1" ] && cd "$1"

echo "PWD=$PWD"

unset IFS

unset DYNAMICALLY_LINKED_EXECUTABLES
unset NEEDED_SYSTEM_SHARED_LIBS
unset FILEPATH_RPATH_MAP

##################################################################

find -type f > fs.txt

while read -r FILEPATH
do
    FILEMAGIC="$(xxd -u -p -l 4 "$FILEPATH")"

    # http://www.sco.com/developers/gabi/latest/ch4.eheader.html
    case $FILEMAGIC in
        2321*)
            Y="$(head -n 1 "$FILEPATH")"

            case "$Y" in
                */bin/ruby*)
                    gsed -i '1c #!/usr/bin/env ruby' "$FILEPATH"
            esac
            ;;
        7F454C46)
            # https://www.sco.com/developers/gabi/latest/ch4.eheader.html
            ELFTYPE="$(xxd -u -p -s 16 -l 2 "$FILEPATH")"

            printf 'ELFTYPE: %s ELFFILE: %s\n' "$ELFTYPE" "$FILEPATH"

            if [ "$ELFTYPE" != '0300' ] && [ "$ELFTYPE" != '0003' ] ; then
                continue
            fi

            check_DT_NEEDED "$FILEPATH"

            [ -x "$FILEPATH" ] || continue

            DYNAMIC_LOADER_FILEPATH="$(patchelf --print-interpreter "$FILEPATH")" || continue

            [ -z "$DYNAMIC_LOADER_FILEPATH" ] && continue

            DYNAMICALLY_LINKED_EXECUTABLES="$DYNAMICALLY_LINKED_EXECUTABLES
$FILEPATH"

            LIBRARY_PATH_RELATIVE_TO_SELF_EXE_PATH="$(realpath -m --relative-to="${FILEPATH%/*}" lib)"

            run chmod -x "$FILEPATH"

            run mv "$FILEPATH" "$FILEPATH.bin"

            DYNAMIC_LOADER_FILENAME="${DYNAMIC_LOADER_FILEPATH##*/}"

            gen_c_source_file "$FILEPATH" "$DYNAMIC_LOADER_FILENAME" "$LIBRARY_PATH_RELATIVE_TO_SELF_EXE_PATH"

            run gcc -static -std=gnu11 -Os -s -flto -o "$FILEPATH" "$FILEPATH.c"
    esac
done < fs.txt

rm fs.txt

##################################################################

[ -n "$NEEDED_SYSTEM_SHARED_LIBS" ] && {
    NEEDED_SYSTEM_SHARED_LIBS="$(printf '%s\n' "$NEEDED_SYSTEM_SHARED_LIBS" | sort | uniq)"
}

[ -n "$FILEPATH_RPATH_MAP" ] && {
    FILEPATH_RPATH_MAP="$(printf '%s\n' "$FILEPATH_RPATH_MAP" | sort | uniq)"
}

##################################################################

cat <<EOF
DYNAMICALLY_LINKED_EXECUTABLES:
$DYNAMICALLY_LINKED_EXECUTABLES

NEEDED_SYSTEM_SHARED_LIBS:
$NEEDED_SYSTEM_SHARED_LIBS

FILEPATH_RPATH_MAP:
$FILEPATH_RPATH_MAP
EOF

##################################################################

[ -z "$DYNAMICALLY_LINKED_EXECUTABLES" ] && abort 1 'no dynamically linked executables found.'

##################################################################

for KV in $FILEPATH_RPATH_MAP
do
    K="${KV%|*}"
    V="${KV#*|}"

    patchelf --print-needed "$K" > /dev/null || continue

    RELATIVE_PATH="$(realpath -m --relative-to="${K%/*}" "$V")"

    run patchelf --add-rpath "'\$ORIGIN/$RELATIVE_PATH'" "$K"
done

##################################################################

[ -n "$NEEDED_SYSTEM_SHARED_LIBS" ] && {
    run install -d lib/

    for f in $NEEDED_SYSTEM_SHARED_LIBS
    do
        run cp -L "'$f'" lib/
    done
}

##################################################################

run cd lib/

[ -f    "$DYNAMIC_LOADER_FILENAME" ] || {
    case $DYNAMIC_LOADER_FILENAME in
        ld-musl-*.so.1)
            run ln -s "libc.musl${DYNAMIC_LOADER_FILENAME#ld-musl}" "$DYNAMIC_LOADER_FILENAME"
    esac
}

##################################################################

success Done.
