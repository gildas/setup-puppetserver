#!/usr/bin/env bash

shopt -s extglob
set -o errtrace
set +o noclobber

export VERBOSE=1
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

function install_package() # {{{
{
  package=$1
  error "The function $FUNCNAME is not implemented yet for $ID version $VERSION_ID"
} # }}}

function enable_service() # {{{
{
  if [[ $ID == 'centos' ]]; then
    if [[ $VERSION_ID == "7" ]]; then
      if ! systemctl -q is-enabled $1 ; then
        verbose "Enabling service $1"
        sudo systemctl -q enable $1
      fi
    else
      error "The function $FUNCNAME is not implemented yet for $ID version $VERSION_ID"
      return 1
    fi
  elif [[ $ID == 'ubuntu' ]]; then
      error "The function $FUNCNAME is not implemented yet for $ID version $VERSION_ID"
      return 1
  fi
} # }}}

function disable_service() # {{{
{
  if [[ $ID == 'centos' ]]; then
    if [[ $VERSION_ID == "7" ]]; then
      if systemctl -q is-enabled $1 ; then
        verbose "Disabling service $1"
        sudo systemctl -q disable $1
      fi
    else
      error "The function $FUNCNAME is not implemented yet for $ID version $VERSION_ID"
      return 1
    fi
  elif [[ $ID == 'ubuntu' ]]; then
    error "The function $FUNCNAME is not implemented yet for $ID version $VERSION_ID"
    return 1
  fi
} # }}}

function start_service() # {{{
{
  if [[ $ID == 'centos' ]]; then
    if [[ $VERSION_ID == "7" ]]; then
      $NOOP sudo systemctl -q start $1
    else
      if service $1 status 2>&1 > /dev/null ; then
        verbose "Starting service $1"
        $NOOP sudo service $1 start
      fi
    fi
  elif [[ $ID == 'ubuntu' ]]; then
    if service $1 status 2>&1 > /dev/null ; then
      verbose "Starting service $1"
      $NOOP sudo service $1 start
    fi
  fi
} # }}}

function stop_service() # {{{
{
  if [[ $ID == 'centos' ]]; then
    if [ "$VERSION_ID" == "7" ]; then
      sudo systemctl -q stop $1
    else
      if ! service $1 status 2>&1 > /dev/null ; then
        verbose "Stopping service $1"
        sudo service $1 stop
      fi
    fi
  elif [[ $ID != 'ubuntu' ]]; then
    if ! service $1 status 2>&1 > /dev/null ; then
      verbose "Stopping service $1"
      sudo service $1 stop
    fi
  fi
} # }}}

function validate_system() # {{{
{
  if [[ $ID == 'centos' ]]; then
    if [[ $VERSION_ID == "7" ]]; then
      supported=1
    else
      echo "We are very sorry, but we cannot complete the automatic installation as the version $VERSION (id=$VERSION_ID) of $NAME is not yet supported."
      exit 1
    fi
  elif [[ $ID == 'ubuntu' ]]; then
    if [[ $VERSION_ID == '14.04' ]]; then
      supported=1
    else
      echo "We are very sorry, but we cannot complete the automatic installation as the version $VERSION (id=$VERSION_ID) of $NAME is not yet supported."
      exit 1
    fi
  else
    echo "We are very sorry, but we cannot complete the automatic installation as the operating system $NAME (id=$ID) is not yet supported."
    exit 1
  fi
} # }}}

function update_system() # {{{
{
  echo "Updating operating system (can take a few minutes)"
  if [[ $ID == 'centos' ]]; then
    $NOOP sudo yum --assumeyes --quiet update
  elif [[ $ID == 'ubuntu' ]]; then
    $NOOP sudo apt-get -y -qq update
    if [[ -z $(dpkg-query -W -f='{Status}' software-properties-common | grep '\s+installed') ]]; then
      $NOOP sudo apt-get -y -qq install software-properties-common
    fi
    if [[ -z $(dpkg-query -W -f='{Status}' apt-file | grep '\s+installed') ]]; then
      $NOOP sudo apt-get -y -qq install apt-file
    fi
    if [[ -z $(apt-cache policy | grep brightbox/ruby-ng) ]]; then
      $NOOP sudo add-apt-repository -y ppa:brightbox/ruby-ng
      $NOOP sudo apt-get -y -qq update
      $NOOP sudo apt-file update 2>&1 > /dev/null &
    fi
  fi
} # }}}

function disable_selinux() # {{{
{
  if [[ $ID == 'centos' ]]; then
    if [[ ! -z $(sestatus | grep -i 'Current mode:.*enforcing') ]]; then
      echo "Disabling runtime SELinux"
      $NOOP sudo setenforce 0
    fi

    if [[ ! -z $(sestatus | grep -i 'Mode from config file:.*enforcing') ]]; then
      echo "Disabling SELinux at boot time"
      $NOOP sudo sed -i "/^\s*SELINUX=/s/.*/SELINUX=permissive/" /etc/selinux/config
    fi
  fi
} # }}}

function set_hostname() # {{{
{
  hostname=$1

  if [[ $(hostname) != $hostname ]]; then
    echo "Updating server hostname to: $hostname"
    if [[ $ID == 'centos' ]]; then
      $NOOP echo "$hostname" | sudo tee /etc/hostname > /dev/null
      $NOOP sudo sed -i "/^\s*127\.0\.0\.1/s/$/ ${hostname}/" /etc/hosts
      if [[ $VERSION_ID == "7" ]]; then
        for interface_config in /etc/sysconfig/network-scripts/ifcfg-* ; do
          interface="$(basename $interface_config | cut --delimiter=- --fields=2)"
          if [[ ! -z $(grep 'BOOTPROTO="dhcp"' $interface_config) ]]; then
            echo "Configuring interface $interface"
            if [[ -z $(grep DHCP_HOSTNAME $interface_config) ]]; then
              $NOOP echo "DHCP_HOSTNAME=\"$hostname\"" | sudo tee --append $interface_config > /dev/null
            else
              $NOOP sudo sed -i "/^DHCP_HOSTNAME/s/\".*\"/\"$hostname\"/" $interface_config
            fi
          fi
        done
        echo "Restarting network"
        $NOOP sudo systemctl restart network
      fi
    elif [[ $ID == 'ubuntu' ]]; then
      if [[ -z $(grep '^\s*send\s*host-name\s*=\s*gethostname();$' /etc/dhcp/dhclient.conf) ]]; then
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
} # }}}

function main() # {{{
{
  hostname=${1:-puppet}

  [[ ! -z $NOOP ]] && echo "Running in dry mode (no command will be executed)"

  # Loads the distro information
  debug "Loading distribution information..."
  source /etc/os-release
  [[ -r /etc/lsb-release ]] && source /etc/lsb-release
  debug "Done\n"
  echo "Running on $NAME release $VERSION"

  validate_system
  echo "To install software and configure your system, you need to be a sudoer and will have to enter your password once during this script."
  disable_selinux
  update_system
  set_hostname $hostname

if ! has_application git ; then
  echo "Installing git"
  if [[ $ID == 'centos' ]]; then
    $NOOP sudo yum install -y git
  elif [[ $ID == 'ubuntu' ]]; then
    $NOOP sudo apt-get -y -qq install git
  fi
fi

if [[ $ID == 'centos' ]]; then
  if [[ -z $(rpm -qa | grep ruby) ]]; then
    echo "Installing Ruby"
    $NOOP sudo yum install -y ruby
  fi
elif [[ $ID == 'ubuntu' ]]; then
  if [[ -z $(dpkg-query -W -f='{Status}' ruby2.1 | grep '\s+installed') ]]; then
    echo "Installing Ruby"
    $NOOP sudo apt-get -y -qq install ruby2.1 ruby2.1-dev
  fi
fi

if [[ -z $(gem list --local | grep diff-lcs) ]] ; then
  echo "Installing gem diff/lcs for Puppet's show_diff option"
  $NOOP sudo gem install --quiet --no-document diff-lcs
fi

if [[ $ID == 'centos' ]]; then
  if [[ -z $(rpm -qa | grep puppet-server) ]]; then
    echo "Installing puppet server"
    if [[ $VERSION_ID == "7" ]]; then
      $NOOP sudo rpm -ivh http://yum.puppetlabs.com/puppetlabs-release-el-7.noarch.rpm
    elif [[ $VERSION_ID == "6" ]]; then
      $NOOP sudo rpm -ivh http://yum.puppetlabs.com/el/6/products/i386/puppetlabs-release-6-7.noarch.rpm
    fi
    $NOOP sudo yum install -y puppet-server
  fi
elif [[ $ID == 'ubuntu' ]]; then
  if [[ -z $(dpkg-query -W -f='{Status}' puppetmaster | grep '\s+installed') ]]; then
    echo "Installing puppet server"
    if [[ $VERSION_ID == '14.04' ]]; then
      $NOOP sudo curl -sSL https://apt.puppetlabs.com/puppetlabs-release-trusty.deb -o /var/cache/apt/puppetlabs-release-trusty.deb
      $NOOP sudo dpkg -i /var/cache/apt/puppetlabs-release-trusty.deb
    elif [[ $VERSION_ID == '12.04' ]]; then
      $NOOP sudo curl -sSL https://apt.puppetlabs.com/puppetlabs-release-precise.deb -o /var/cache/apt/puppetlabs-release-precise.deb
      $NOOP sudo dpkg -i /var/cache/apt/puppetlabs-release-precise.deb
    fi
    $NOOP sudo apt-get -y -qq update
    $NOOP sudo apt-get -y -qq install puppetmaster-passenger
  fi
fi

  # Make sure puppet server is off for a while
  stop_service puppetmaster

  if [[ ! -d /etc/puppet/.git ]]; then
    echo "Cloning puppet configuration"
    $NOOP sudo rm -rf /etc/puppet /etc/hiera.yaml
    $NOOP sudo git clone http://github.com/gildas/config-puppetserver.git /etc/puppet
    $NOOP sudo ln -s /etc/puppet/hiera.yaml /etc/hiera.yaml
    $NOOP sudo chown -R puppet:puppet /etc/puppet
  else
    echo "Updating puppet configuration"
    $NOOP sudo sh -c "cd /etc/puppet && git pull"
    $NOOP sudo chown -R puppet:puppet /etc/puppet
  fi

  [[ -d /var/lib/puppet/hiera ]] || $NOOP mkdir -p /var/lib/puppet/hiera 
  if [[ -d /var/lib/puppet/hiera/.git ]]; then
    verbose "Updating hiera profiles"
    $NOOP sudo sh -c "cd /var/lib/puppet/hiera && git pull"
  else
    verbose "Cloning hiera profiles"
    $NOOP sudo git clone git://repo.apac.inin.com/hiera-data.git /var/lib/puppet/hiera
  fi
  $NOOP sudo chown -R puppet:puppet /var/lib/puppet/hiera

  if [[ -z $(gem list --local | grep librarian-puppet) ]] ; then
    echo "Installing librarian for puppet"
    $NOOP sudo gem install --quiet --no-document librarian-puppet

    echo "First run of librarian (This can some time...)"
    $NOOP sudo sh -c "cd /etc/puppet && /usr/local/bin/librarian-puppet update --verbose 2>&1 | tee -a /var/log/puppet/librarian.log > /dev/null"
  fi

if [[ $ID == 'centos' ]]; then
  enable_service puppetmaster
  start_service  puppetmaster
fi

# TODO: Install Passenger, rack, etc. to run puppet master not in Webrick
# See: https://docs.puppetlabs.com/guides/passenger.html

  verbose "Enabling and Starting Puppet agent"
  sudo puppet resource service puppet ensure=running enable=true
  #verbose "Adding a cron job for the puppet agent"
  #sudo puppet resource cron puppet-agent ensure=present user=root minute=30 command='/usr/bin/puppet agent --onetime --no-daemonize --splay'

  # TODO: Open the firewall: puppet mater: 8140
# TODO: Should we use jenkins too?
} # }}}

main
