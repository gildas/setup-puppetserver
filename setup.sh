#!/usr/bin/env bash

shopt -s extglob
set -o errtrace
set +o noclobber

#export VERBOSE=1
#export DEBUG=1
export NOOP=

whoami=$(whoami)

function log() # {{{
{
  printf "%b\n" "$*";
} # }}}

function debug() # {{{
{
  [[ ${DEBUG:-0} -eq 0 ]] || printf "[debug] $#: $*";
} # }}}

function verbose() # {{{
{
  [[ ${VERBOSE:-0} -eq 0 ]] || printf "$*\n";
} # }}}

function error() # {{{
{
  echo >&2 "$@"
} # }}}

function prompt() # {{{
{
  while true; do
  read -p "$1" response
    case $response in
      [Yy]|[Yy][Ee][Ss]) return 0;;
      [Nn]|[Nn][Oo])     return 1;;
      *) echo "Please answer yes or no";;
    esac
  done
} # }}}

function has_application() # {{{
{
  command -v "$@" > /dev/null 2>&1
} # }}}

# Main {{{
hostname=${1:-puppet}

[[ ! -z "$NOOP" ]] && echo "Running in dry mode (no command will be executed)"

# Loads the distro information
debug "Loading distribution information..."
source /etc/os-release
[[ -r /etc/lsb-release ]] && source /etc/lsb-release
debug "Done\n"
echo "Running on $NAME release $VERSION"
echo "To install software and configure your system, you need to be a sudoer and will have to enter your password once during this script."

if [[ "$(hostname)" != "$hostname" ]] ; then
  echo "Updating server hostname to: $hostname"
  $NOOP echo "$hostname" | sudo tee /etc/hostname > /dev/null
  if [ "$ID" == "centos" ] ; then
    if [ "$VERSION_ID" == "7" ] ; then
      for interface_config in /etc/sysconfig/network-scripts/ifcfg-* ; do
        interface="$(basename $interface_config | cut --delimiter=- --fields=2)"
        if [ ! -z "$(grep 'BOOTPROTO="dhcp"' $interface_config)" ] ; then
          echo "Configuring interface $interface"
          if [ -z "$(grep DHCP_HOSTNAME $interface_config)" ] ; then
            $NOOP echo "DHCP_HOSTNAME=\"$hostname\"" | sudo tee --append $interface_config > /dev/null
          else
            $NOOP sudo sed -i "/^DHCP_HOSTNAME/s/\".*\"/\"$hostname\"/" $interface_config
          fi
        fi
      done
      echo "Restarting network"
      $NOOP sudo systemctl restart network
    fi
  fi
fi
# }}}
