#!/bin/zsh

set -e -u

. ./core/host/pushcommon.sh

pushsrc() {
  dopushcompile core/util/compileall.lua
  dopushlua     core/net/nwfmqtt.lua
  dopushlua     core/util/ow-ds18b20.lua
  dopushlua     core/util/i2cu.lua
  dopushlua     thermostat.lua
  dopushlua     init3.lua
  dopushcompile init2.lua
}

if [ -n "${2:-}" ]; then
  if [ -d $2 ]; then CONFDIR=$2
  else echo "Not a directory: $2"; exit 1
  fi
fi

pushconf() {
  if [ -z "${CONFDIR:-}" ]; then
    echo "Asked to push config without specifying?"
    exit 1
  fi
  for f in ${CONFDIR}/*; do
    dopushtext "$f"
  done
}

case "${1:-}" in
  all)
    pushconf
    pushsrc
    ./core/host/pushinit.sh
    ;;
  both)
    pushconf
    pushsrc
    ;;
  src)
    pushsrc
    ;;
  conf)
    pushconf
    ;;
  *)
    echo "Please specify push mode: {conf,src,both,all}"
    exit 1
    ;;
esac
