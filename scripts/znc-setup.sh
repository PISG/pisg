#!/bin/bash
# Put converted channel logs into a ZNC account's log folder and let pisg (a different Unix user) read it.
#
#   bash scripts/znc-setup.sh            show what it found and what it would do (changes nothing)
#   bash scripts/znc-setup.sh --apply    do it
# Run it as the ZNC account (no sudo needed) or with sudo; with sudo it uses a new group "pisg" instead.
#
# What --apply does, in order (nothing is deleted or overwritten):
#   1. finds ZNC's log folder for the account (the log module's  moddata/log ),
#   2. makes a group "pisg" holding the pisg user; the folders leading to the logs get group-execute
#      (a path through them, no listing) and ONLY the channel folders being imported get group-read.
#      Other networks and private-message logs stay owner-only. Files ZNC adds to those channel
#      folders later are world-readable by ZNC's own umask, so they follow the folder's access,
#   3. copies the staged logs  ~/znc-import/#channel/*.log  into  <network>/<channel>/  ("cp -n": an
#      existing day file is never replaced),
#   4. links  ~/znc-logs/<channel>  to those folders, so pisg.cfg never has to know ZNC's layout.
#
# Settings (environment): PISG_USER (required: the unix user that runs pisg), ZNC_HOME (default ~/.znc),
# STAGE (default: ~/znc-import of that user), LINKS (~/znc-logs of that user), NETWORK (only needed if the account has several networks or no log yet).
set -euo pipefail

ZNC_HOME=${ZNC_HOME:-$HOME/.znc}
PISG_USER=${PISG_USER:-}
[ -n "$PISG_USER" ] || { echo "Set PISG_USER to the unix user that runs pisg, e.g.  PISG_USER=pisguser bash $0"; exit 1; }
PISG_HOME=$(getent passwd "$PISG_USER" | cut -d: -f6)
STAGE=${STAGE:-$PISG_HOME/znc-import}
LINKS=${LINKS:-$PISG_HOME/znc-logs}
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
# As root: a dedicated group "pisg". As the ZNC account itself (no sudo needed): the existing group
# "users", which both accounts are in (it has to be a group the ZNC account already belongs to).
if [ "$(id -u)" = 0 ]; then ROOTMODE=1; GROUP=${GROUP:-pisg}; else ROOTMODE=0; GROUP=${GROUP:-users}; fi
if [ "$ROOTMODE" = 0 ] && [ "$APPLY" = 1 ] && [ ! -O "$ZNC_HOME" ]; then
  echo "Run this as the ZNC account (owner of $ZNC_HOME), or with sudo."; exit 1
fi

say() { printf '%s\n' "$*"; }
run() { if [ "$APPLY" = 1 ]; then "$@"; else say "   would run: $*"; fi; }

# 1. where does the log module write?
mapfile -t ROOTS < <(find "$ZNC_HOME" -type d -path '*/moddata/log' 2>/dev/null | sort)
if [ -n "${LOGROOT:-}" ]; then ROOTS=("$LOGROOT"); fi
say "ZNC folder: $ZNC_HOME"
if [ "${#ROOTS[@]}" -ne 1 ]; then
  say "Found ${#ROOTS[@]} log folders (need exactly one):"; printf '  %s\n' "${ROOTS[@]:-}"
  say "Load the log module first (/msg *status LoadMod log), or set LOGROOT=/path/to/moddata/log"
  exit 2
fi
LOGROOT=${ROOTS[0]}
say "log module folder: $LOGROOT"

case "$LOGROOT" in
  */networks/*/moddata/log) BASE=$LOGROOT ;;                               # network scope:  $WINDOW/...
  */users/*/moddata/log)                                                   # user scope:     $NETWORK/$WINDOW/...
    if [ -z "${NETWORK:-}" ]; then
      mapfile -t NETS < <(find "$LOGROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
      if [ "${#NETS[@]}" -eq 1 ]; then NETWORK=${NETS[0]}
      else say "Networks found in it: ${NETS[*]:-none}"; say "Pass NETWORK=<name> (say something in a channel first if there is none yet)"; exit 2; fi
    fi
    BASE=$LOGROOT/$NETWORK ;;
  *) say "Global-scope log module (folder holds \$USER/\$NETWORK/...): pass LOGROOT= pointing at the network folder"; exit 2 ;;
esac
say "network folder: $BASE"
say "staged logs: $STAGE"
ls -d "$STAGE"/'#'* >/dev/null 2>&1 || { say "nothing staged in $STAGE"; exit 2; }

# 2. group and permissions
say; say "== access for $PISG_USER"
if [ "$ROOTMODE" = 1 ]; then
  getent group "$GROUP" >/dev/null || run groupadd "$GROUP"
  id -nG "$PISG_USER" | tr ' ' '\n' | grep -qx "$GROUP" || run usermod -aG "$GROUP" "$PISG_USER"
else
  id -nG "$PISG_USER" | tr ' ' '\n' | grep -qx "$GROUP" || { say "$PISG_USER is not in group $GROUP; run with sudo instead"; exit 1; }
fi
say " group used for read access: $GROUP"
d=$LOGROOT
CHAIN=()
while [ "$d" != "/" ] && [ "$d" != "$(dirname "$ZNC_HOME")" ]; do CHAIN+=("$d"); d=$(dirname "$d"); done
CHAIN+=("$(dirname "$ZNC_HOME")")
for d in "${CHAIN[@]}" "$BASE"; do
  [ -d "$d" ] || continue
  run chgrp "$GROUP" "$d"; run chmod g+x "$d"                              # a way through, no listing
done
# Only the channel folders named below become readable. Other networks and private-message logs
# under the same log folder keep their owner-only permissions.

# 3. copy the staged logs
say; say "== logs"
ZNC_OWNER=$(stat -c %U "$LOGROOT" 2>/dev/null || id -un)
[ "$APPLY" = 1 ] && mkdir -p "$BASE" && chown "$ZNC_OWNER:$GROUP" "$BASE" && chmod 2710 "$BASE"
for s in "$STAGE"/'#'*; do
  name=$(basename "$s")
  existing=$(find "$BASE" -mindepth 1 -maxdepth 1 -type d -iname "$name" 2>/dev/null | head -1 || true)
  dest=${existing:-$BASE/$name}
  n=$(find "$s" -name '*.log' | wc -l)
  say " $name: $n day files -> $dest $([ -n "$existing" ] && echo '(folder already there)' || echo '(new folder)')"
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$dest"; chown "$ZNC_OWNER:$GROUP" "$dest"; chmod 2750 "$dest"
    cp --update=none --no-preserve=mode,ownership "$s"/*.log "$dest"/
    chown "$ZNC_OWNER:$GROUP" "$dest"/*.log
    find "$dest" -type f -name '*.log' -exec chmod 640 {} +
  fi
  # 4. link for pisg (lower case, no #)
  link=$LINKS/$(echo "${name#\#}" | tr 'A-Z' 'a-z')
  if [ "$APPLY" = 1 ] && [ "$ROOTMODE" = 1 ]; then
    mkdir -p "$LINKS"; chown "$PISG_USER" "$LINKS"
    ln -sfn "$dest" "$link"          # (no chown -h: on this system it follows the link and changes the target)
  elif [ "$APPLY" = 1 ]; then
    say "   (links are made by $PISG_USER afterwards: $link -> $dest)"
  else
    say "   would link $link -> $dest"
  fi
done

if [ "$APPLY" = 1 ] && [ "$ROOTMODE" = 1 ]; then
  say; say "== check: what $PISG_USER can now see"
  for l in "$LINKS"/*; do
    printf ' %s: ' "$l"
    setpriv --reuid="$PISG_USER" --regid="$PISG_USER" --groups="$GROUP" ls "$l/" | wc -l | tr '\n' ' '; say "files readable"
  done
  say; say "Done. New group membership reaches $PISG_USER's cron jobs on their next run."
elif [ "$APPLY" = 1 ]; then
  say; say "Done. Tell $PISG_USER it finished: the links and the pisg run come next."
else
  say; say "Nothing changed. Run again with --apply to do it."
fi
