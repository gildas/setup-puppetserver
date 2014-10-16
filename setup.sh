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

function compare_versions () # {{{
{
  # Compare version numbers

  # Versions are same?
  [[ $1 == $2 ]] && return 0

  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)) ; do
    ver1[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++)) ; do
    # fill empty fields in ver2 with zeros
    [[ -z ${ver2[i]} ]] && ver2[i]=0
    # ver1 is bigger than ver2
    [[ 10#${ver1[i]} > 10#${ver2[i]} ]] && return 1
    # ver1 is smaller than ver2
    [[ 10#${ver1[i]} < 10#${ver2[i]} ]] && return 2
  done
  # Versions are same
  return 0
} # }}}

function has_application() # {{{
{
  command -v "$@" > /dev/null 2>&1
} # }}}

function is_service_enabled() # {{{
{
  if [ "$ID" == 'centos' ] ; then
    if [ "$VERSION_ID" == "7" ]; then
      systemctl -q is-enabled $1
    else
      return 1
    fi
  elif [ "$ID" != 'ubuntu' ] ; then
      return 1
  else
    return 1
  fi
} # }}}

function service_enable() # {{{
{
  if [ "$ID" == 'centos' ] ; then
    if [ "$VERSION_ID" == "7" ]; then
      sudo systemctl -q enable $1
    else
      return 1
    fi
  elif [ "$ID" != 'ubuntu' ] ; then
      return 1
  else
    return 1
  fi
} # }}}

function service_disable() # {{{
{
  if [ "$ID" == 'centos' ] ; then
    if [ "$VERSION_ID" == "7" ]; then
      sudo systemctl -q disable $1
    else
      return 1
    fi
  elif [ "$ID" != 'ubuntu' ] ; then
      return 1
  else
    return 1
  fi
} # }}}

function is_service_running() # {{{
{
  if [ "$ID" == 'centos' ] ; then
    if [ "$VERSION_ID" == "7" ]; then
      systemctl -q is-active $1
    else
      return 1
    fi
  elif [ "$ID" != 'ubuntu' ] ; then
    if [ ! -z "$(service $1 status | grep 'is running$')" ] ; then
      return 0
    else
      return 1
    fi
  else
    return 1
  fi
} # }}}

function service_start() # {{{
{
  if [ "$ID" == 'centos' ] ; then
    if [ "$VERSION_ID" == "7" ]; then
      sudo systemctl -q start $1
    else
      return 1
    fi
  elif [ "$ID" != 'ubuntu' ] ; then
      sudo service $1 start
  else
    return 1
  fi
} # }}}

function service_stop() # {{{
{
  if [ "$ID" == 'centos' ] ; then
    if [ "$VERSION_ID" == "7" ]; then
      sudo systemctl -q stop $1
    else
      return 1
    fi
  elif [ "$ID" != 'ubuntu' ] ; then
      sudo service $1 stop
  else
    return 1
  fi
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

if [ "$ID" == 'centos' ] ; then
  if [ "$VERSION_ID" == "7" ]; then
    supported=1
  else
	  echo "We are very sorry, but we cannot complete the automatic installation as the version $VERSION (id=$VERSION_ID) of $NAME is not yet supported."
    exit 1
  fi
elif [ "$ID" == 'ubuntu' ] ; then
  if [ "$VERSION_ID" == '14.04' ]; then
    supported=1
  else
    echo "We are very sorry, but we cannot complete the automatic installation as the version $VERSION (id=$VERSION_ID) of $NAME is not yet supported."
    exit 1
  fi
else
  echo "We are very sorry, but we cannot complete the automatic installation as the operating system $NAME (id=$ID) is not yet supported."
  exit 1
fi

echo "To install software and configure your system, you need to be a sudoer and will have to enter your password once during this script."

if [ "$ID" == 'centos' ] ; then
  if [[ ! -z "$(sestatus | grep -i 'Current mode:.*enforcing')" ]] ; then
    echo "Disabling runtime SELinux"
    $NOOP sudo setenforce 0
  fi

  if [[ ! -z "$(sestatus | grep -i 'Mode from config file:.*enforcing')" ]] ; then
    echo "Disabling SELinux at boot time"
    $NOOP sudo sed -i "/^\s*SELINUX=/s/.*/SELINUX=permissive/" /etc/selinux/config
  fi
fi

if [[ "$(hostname)" != "$hostname" ]] ; then
  echo "Updating server hostname to: $hostname"
  if [ "$ID" == "centos" ] ; then
    $NOOP echo "$hostname" | sudo tee /etc/hostname > /dev/null
    $NOOP sudo sed -i "/^\s*127\.0\.0\.1/s/$/ ${hostname}/" /etc/hosts
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
  elif [ "$ID" == "ubuntu" ] ; then
    if [ -z "$(grep '^\s*send\s*host-name\s*=\s*gethostname();$' /etc/dhcp/dhclient.conf)" ] ; then
      echo "Warning: Your DHCP configuration is not set to send the hostname to the DHCP server (useful for Dynamic DNS)"
      echo "         Add the line \"send host-name = gethostname();\" to your /etc/dhcp/dhclient.conf"
    fi
    # We need to keep both hostnames until services are reset or sudo breaks
    $NOOP sudo sed -i "/^\s*127\.0\.1\.1/s/$/ ${hostname}/" /etc/hosts
    $NOOP sudo hostnamectl set-hostname ${hostname}
    echo "Restarting network"
    $NOOP sudo service hostname start
    $NOOP sudo service networking restart
    # Now it is safe to forget the old hostname
    $NOOP sudo sed -i "/^\s*127\.0\.1\.1/s/^.*$/127.0.1.1\t${hostname}/" /etc/hosts
  fi
fi

if ! has_application git ; then
  echo "Installing git"
  if [ "$ID" == "centos" ] ; then
    $NOOP sudo yum install -y git
  elif [ "$ID" == "ubuntu" ] ; then
    $NOOP sudo apt-get -y install git
  fi
fi

if ! has_application gem ; then
  if [ "$ID" == "centos" ] ; then
    echo "Installing rubygems"
    $NOOP sudo yum install -y rubygems
  elif [ "$ID" == "ubuntu" ] ; then
    echo "Installing rubygems"
    $NOOP sudo apt-get -y install rubygems
  fi
fi

compare_versions $(ruby -v | cut -d ' ' -f 2 | cut -d p -f 1) 1.9.3
if [[ $? == 2 ]] ; then
  echo "Your ruby is too old ($(ruby -v)), you need to run at least version 1.9.3"
  exit 1
fi

if [ "$ID" == "centos" ] ; then
  if [ -z "$(rpm -qa | grep puppet-server)" ] ; then
    echo "Installing puppet"
    if [ "$VERSION_ID" == "7" ] ; then
      $NOOP sudo rpm -ivh http://yum.puppetlabs.com/puppetlabs-release-el-7.noarch.rpm
    elif [ "$VERSION_ID" == "6" ] ; then
      $NOOP sudo rpm -ivh http://yum.puppetlabs.com/el/6/products/i386/puppetlabs-release-6-7.noarch.rpm
    fi
    $NOOP sudo yum install -y puppet-server
  fi
elif [ "$ID" == "ubuntu" ] ; then
  if [ -z "$(dpkg-query -W -f='{Status}' puppetmaster | grep '\s+installed')" ] ; then
    echo "Installing puppet"
    if [ "$VERSION_ID" == "14.04" ] ; then
      $NOOP sudo curl -sSL https://apt.puppetlabs.com/puppetlabs-release-trusty.deb -o /var/cache/apt/puppetlabs-release-trusty.deb
      $NOOP sudo dpkg -i /var/cache/apt/puppetlabs-release-trusty.deb
    elif [ "$VERSION_ID" == "12.04" ] ; then
      $NOOP sudo curl -sSL https://apt.puppetlabs.com/puppetlabs-release-precise.deb -o /var/cache/apt/puppetlabs-release-precise.deb
      $NOOP sudo dpkg -i /var/cache/apt/puppetlabs-release-precise.deb
    fi
    $NOOP sudo apt-get -y update
    $NOOP sudo apt-get -y install puppetmaster-passenger
    $NOOP sudo apt-get -y install puppetmaster
  fi
fi

if [[ ! -d /etc/puppet/.git ]] ; then
  echo "Cloning puppet configuration"
  $NOOP sudo rm -rf /etc/puppet /etc/hiera.yaml
  $NOOP sudo git clone http://github.com/gildas/config-puppetserver.git /etc/puppet
  $NOOP sudo ln -s /etc/puppet/hiera.yaml /etc/hiera.yaml
else
  $NOOP sudo sh -c "cd /etc/puppet && git pull"
fi

#[[ -d /var/lib/puppet/ssl ]] || $NOOP sudo mkdir -p /var/lib/puppet/ssl
#$NOOP sudo chown -R puppet:puppet /var/lib/puppet/client* /var/lib/puppet/lib /var/lib/puppet/ssl

if [[ -z "$(gem list --local | grep librarian-puppet)" ]] ; then
  echo "Installing librarian for puppet"
  if [ "$ID" == "centos" ] ; then
    if [ "$VERSION_ID" == "7" ] ; then
      $NOOP sudo gem install --quiet --no-document librarian-puppet
    else
      $NOOP sudo gem install --quiet --no-rdoc --no-ri librarian-puppet
    fi
  elif [ "$ID" == "ubuntu" ] ; then
    $NOOP sudo gem install --quiet --no-rdoc --no-ri librarian-puppet
  fi

  echo "First run of librarian (This can some time...)"
  $NOOP sudo sh -c "cd /etc/puppet && /usr/local/bin/librarian-puppet update --verbose 2>&1 | tee -a /var/log/puppet/librarian.log > /dev/null"
fi

if ! is_service_enabled puppetmaster ; then
  echo "Enabling puppet master service"
  service_enable puppetmaster
fi

if ! is_service_running puppetmaster ; then
  echo "Starting puppet master service"
  service_start puppetmaster
fi
# }}}
