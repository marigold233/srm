#!/usr/bin/env bash
set -e 



#!/usr/bin/env bash

# ==== CONFIGURATION ====
find_config() {
    for conf in "$HOME/.config/srm/config" "$HOME/.srmConfig" ".srmConfig"; do
        [ -f "$conf" ] && . "$conf" && return 0
    done
}
find_config

: "${TRASH_DIR:="$HOME/.trash"}"
: "${SIZE_THRESHOLD_MB:=10M}"
: "${LOG_FILE:="$TRASH_DIR/trash.csv"}"

# ==== BASIC HELP ====
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]... [FILE]...
Options:
  -e        Empty the trash bin completely.
  -c DAYS   Clean trash files older than DAYS.
  -r NAME   Restore file(s) matching NAME from trash.
  -f FILE   Force (permanent) delete FILE (bypass trash).
  -h        Show this help.
If no options given, FILEs are moved to the trash (safely removed).
EOF
}

# ==== LOGGING ====
log_msg() {
    local lvl=${1:-INFO} msg=$2 who=${3:-main}
    printf 'timestamp=%s level=%s component=%s pid=%d message=%s\n' \
        "$(date --iso-8601=seconds)" "$lvl" "$who" "$$" "$msg" >&2
}

# ==== ENVIRONMENT SETUP ====
setup_env() {
    mkdir -p "$TRASH_DIR"
    [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ] || printf "file,dir,trashed,mime,time\n" > "$LOG_FILE"
    SIZE_THRESHOLD_BYTES=$(numfmt --from=iec "$SIZE_THRESHOLD_MB")
}

# ==== CSV LOGGING (/TRASH BIN LOGIC) ====
csv_add()   { echo "$*" >>"$LOG_FILE"; }
csv_delete(){ awk -F',' -v f="$1" '$3!=f' "$LOG_FILE" >"$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"; }
csv_search(){ awk -F',' -v k="$1" 'tolower($1) ~ tolower(k)' "$LOG_FILE"; }

# ==== REMOVE FILES(TO TRASH OR DIRECT DELETE) ====
remove_files() {
    local file qtrash=() qdelete=()
    for file; do
        [ ! -e "$file" ] && log_msg ERROR "$file not found" && continue
        local abs=$(readlink -f "$file")
        local size
        if [ -f "$abs" ]; then size=$(stat -c%s "$abs")
        elif [ -d "$abs" ]; then size=$(du -bs "$abs"|awk '{print $1}')
        else log_msg ERROR "$file is not a file/dir" && continue
        fi
        if [ "$size" -le "$SIZE_THRESHOLD_BYTES" ]; then
            qtrash+=("$abs")
        else
            qdelete+=("$abs")
        fi
    done

    # Trash move
    for file in "${qtrash[@]}"; do
        local orig=$(basename "$file")
        local dir=$(dirname "$file")
        local ts=$EPOCHSECONDS
        local trashname="${orig}_$ts"
        local mimetype=$(file -b --mime-type "$file")
        local timestr=$(date +"%F %T" -d@"$ts")
        if mv "$file" "$TRASH_DIR/$trashname"; then
            csv_add "$orig","$dir","$trashname","$mimetype","$timestr"
            printf '.'
        else
            log_msg ERROR "Move failed $file"
        fi
    done; [ "${#qtrash[@]}" -gt 0 ] && echo

    # Direct delete
    for file in "${qdelete[@]}"; do
        [[ "$file" == "/" || "$file" == "$HOME" ]] && log_msg ERROR "Refuse to delete $file" && continue
        rm -rf -- "$file"
        log_msg INFO "Deleted large file $file"
    done
}

# ==== FORCE DELETE ====
force_delete() {
    for f; do
        [[ "$f" == "/" || "$f" == "$HOME" ]] && log_msg ERROR "Dangerous path: $f" && continue
        rm -rf -- "$f"
        log_msg INFO "Force deleted $f"
    done
}

# ==== RESTORE FILES ====
restore_file() {
    local query=$1
    mapfile -t hits < <(csv_search "$query")
    [ "${#hits[@]}" -eq 0 ] && log_msg ERROR "No match for $query" && return 1
    local i; for i in "${!hits[@]}"; do
        IFS=, read -r fname fdir tname _ tstr <<<"${hits[$i]}"
        printf "%2d) %s (from %s, trashed on %s)\n" "$i" "$fname" "$fdir" "$tstr"
    done
    read -r -p "Select number to restore: " idx
    [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 0 ] && [ "$idx" -lt "${#hits[@]}" ] || \
        { log_msg ERROR "Invalid index $idx"; return 2; }
    IFS=, read -r fname fdir tname _ <<<"${hits[$idx]}"
    if mv -i "$TRASH_DIR/$tname" "$fdir/$fname"; then
        csv_delete "$tname"
        log_msg INFO "Restored $fdir/$fname"
    else
        log_msg ERROR "Restore failed $tname"
    fi
}

# ==== CLEAN OLD TRASH ====
clean_old_trash() {
    local days=$1
    find "$TRASH_DIR" -mindepth 1 -mtime +"$days" -exec rm -rf -- {} +
}

# ==== EMPTY BIN ====
empty_trash() {
    read -r -p "Empty trash bin (irreversible)? [y/N]: " y
    [[ "$y" =~ ^[Yy]$ ]] || return 0
    [[ "$TRASH_DIR" == "/" || "$TRASH_DIR" == "$HOME" || -z "$TRASH_DIR" ]] && \
        log_msg ERROR "Unsafe TRASH_DIR '$TRASH_DIR'" && return 1
    rm -rf -- "$TRASH_DIR"/*
    > "$LOG_FILE"
    log_msg INFO "Trash emptied"
}

# ==== MAIN ENTRY ====
main() {
    setup_env
    local opt force_queue=()
    while getopts "hec:r:f:" opt; do
        case "$opt" in
            h) usage; exit 0;;
            e) empty_trash; exit $?;;
            c) clean_old_trash "$OPTARG"; exit $?;;
            r) restore_file "$OPTARG"; exit $?;;
            f) force_queue+=("$OPTARG");;
            *) usage; exit 1;;
        esac
    done
    shift $((OPTIND - 1))
    if [ "${#force_queue[@]}" -gt 0 ]; then
        force_delete "${force_queue[@]}"
        exit 0
    fi
    [ $# -eq 0 ] && usage && exit 1
    remove_files "$@"
}

main "$@"