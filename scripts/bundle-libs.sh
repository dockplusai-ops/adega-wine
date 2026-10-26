#!/bin/bash
# Makes a Wine install self-contained: copies every Homebrew dylib it needs into <wine>/lib.
#
# Same layout as Gcenx's macOS builds:
#   - third-party dylibs live in lib/, named by their file name and depending on each
#     other through @loader_path/
#   - Wine's unix libraries (lib/wine/x86_64-unix/*.so) reach them through @rpath,
#     with rpath @loader_path/../../ ; binaries in bin/ through @executable_path/../lib
#   - libraries Wine only dlopen()s (configure's SONAME_* list) are passed as arguments
#
# Usage: bundle-libs.sh <wine install root> [dylib Wine dlopen()s ...]
set -euo pipefail

WINE=$1; shift
LIB=$WINE/lib
BREW=$(brew --prefix)

is_external() { case "$1" in "$BREW"/*|/usr/local/*|/opt/homebrew/*) return 0 ;; *) return 1 ;; esac; }
deps() { otool -L "$1" | tail -n +2 | awk '{print $1}'; }
is_macho() { file -b "$1" | grep -q Mach-O; }

copied=" "   # bash 3.2 (macOS /bin/bash) has no associative arrays
queue=("$@")

# Wine's own Mach-O files: point their Homebrew dependencies at @rpath and queue them.
while IFS= read -r -d '' file; do
    is_macho "$file" || continue
    case "$file" in
        "$WINE"/bin/*) rpath=@executable_path/../lib ;;
        "$WINE"/lib/wine/*) rpath=@loader_path/../../ ;;
        *) continue ;;
    esac
    changed=0
    for dep in $(deps "$file"); do
        is_external "$dep" || continue
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$file"
        queue+=("$dep")
        changed=1
    done
    if [ $changed = 1 ] && ! otool -l "$file" | grep -q "path $rpath "; then
        install_name_tool -add_rpath "$rpath" "$file"
    fi
done < <(find "$WINE/bin" "$WINE/lib/wine" -type f -print0)

# Copy the queue (and what it depends on) into lib/.
while [ ${#queue[@]} -gt 0 ]; do
    dep=${queue[0]}; queue=("${queue[@]:1}")
    name=$(basename "$dep")
    case "$copied" in *" $name "*) continue ;; esac
    copied="$copied$name "
    target=$LIB/$name
    cp -L "$dep" "$target"
    chmod u+w "$target"
    install_name_tool -id "$name" "$target"
    for sub in $(deps "$target"); do
        is_external "$sub" || continue
        install_name_tool -change "$sub" "@loader_path/$(basename "$sub")" "$target"
        queue+=("$sub")
    done
    echo "bundled $name"
done

# install_name_tool invalidates signatures; macOS refuses to load unsigned code.
# (if, not &&: a false test as the loop's last command would stop the script under set -e)
find "$WINE/bin" "$WINE/lib" -type f -print0 | while IFS= read -r -d '' file; do
    if is_macho "$file"; then codesign --force --sign - "$file"; fi
done

# Nothing may still point into Homebrew.
leftovers=$(find "$WINE" -type f -print0 | while IFS= read -r -d '' f; do
    if is_macho "$f"; then
        deps "$f" | while read -r d; do if is_external "$d"; then echo "$f -> $d"; fi; done
    fi
done)
if [ -n "$leftovers" ]; then
    echo "Still linked to Homebrew:"; echo "$leftovers"; exit 1
fi
echo "bundle-libs: $(echo $copied | wc -w | tr -d ' ') libraries"
