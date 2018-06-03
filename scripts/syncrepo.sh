#!/bin/bash

# This is a simple mirroring script. To save bandwidth it first checks a
# timestamp via HTTP and only runs rsync when the timestamp differs from the
# local copy. As of 2016, a single rsync run without changes transfers roughly
# 6MiB of data which adds up to roughly 250GiB of traffic per month when rsync
# is run every minute. Performing a simple check via HTTP first can thus save a
# lot of traffic.

# Directory where the repo is stored locally. Example: /srv/repo (absolute PATH)
target="/srv/blackarch/target"

# Directory where files are downloaded to before being moved in place.
# This should be on the same filesystem as $target, but not a subdirectory of $target.
# Example: /srv/tmp
tmp="/srv/blackarch/tmp"

# Lockfile path
lock="/var/lock/syncrepo.lck"

# If you want to limit the bandwidth used by rsync set this.
# Use 0 to disable the limit.
# The default unit is KiB (see man rsync /--bwlimit for more)
bwlimit=0

# The source URL of the mirror you want to sync from.
source_url='rsync://blackarch.org/blackarch/'

# An HTTP(S) URL pointing to the 'lastupdate' file on your chosen mirror.
# Otherwise use the HTTP(S) URL from your chosen mirror.
lastupdate_url='https://blackarch.org/blackarch/lastupdate'

#### END CONFIG

trap interrupted INT
trap interrupted EXIT

function interrupted() {
    rm -rfv "${lock}"
}

[ ! -d "${target}" ] && mkdir -p "${target}"
[ ! -d "${tmp}" ] && mkdir -p "${tmp}"

exec 9>"${lock}"
flock -n 9 || exit

rsync_cmd() {
    local -a cmd=(rsync -rtlH --safe-links --delete-after ${VERBOSE} "--timeout=600" -p \
        --delay-updates --no-motd "--temp-dir=${tmp}")

    if stty &>/dev/null; then
        cmd+=(-h -v --progress)
    else
        cmd+=(--quiet)
    fi

    if ((bwlimit>0)); then
        cmd+=("--bwlimit=$bwlimit")
    fi

    "${cmd[@]}" "$@"
}


# if we are called without a tty (cronjob) only run when there are changes
if ! tty -s && [[ -f "$target/lastupdate" ]] && diff -b <(curl -Ls "$lastupdate_url") "$target/lastupdate" >/dev/null; then
    rsync_cmd "$source_url/lastsync" "$target/lastsync"
    exit 0
fi

rsync_cmd \
    "${source_url}" \
    "${target}"

#echo "Last sync was $(date -d @$(cat ${target}/lastsync))"
