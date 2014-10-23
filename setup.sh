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
        $NOOP sudo systemctl -q enable $1
      fi
    else
      error "The function $FUNCNAME is not implemented yet for $ID version $VERSION_ID"
      return 1
    fi
  elif [[ $ID == 'ubuntu' ]]; then
    if [[ ! -z $(status $1 2>&1 | grep 'Unknown job') ]]; then
      # Old fashion System/V init service
      $NOOP sudo update-rc.d $1 defaults
    else
      $NOOP sudo rm -f /etc/init/$1.conf.override
    fi
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
    if [[ ! -z $(status $1 2>&1 | grep 'Unknown job') ]]; then
      # Old fashion System/V init service
      $NOOP sudo update-rc.d $1 disable
    else
      $NOOP echo manual | sudo tee /etc/init/$1.conf.override > /dev/null
    fi
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
    if [[ -z $(dpkg-query -W -f='{Status}' software-properties-common 2>&1 | grep '\s+installed') ]]; then
      $NOOP sudo apt-get -y -qq install software-properties-common
    fi
    if [[ -z $(dpkg-query -W -f='{Status}' apt-file 2>&1 | grep '\s+installed') ]]; then
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
              $NOOP sudo sed -i "/^DHCP_HOSTNAME/s/\".*\"/\"$hostname ${hostname}.localdomain\"/" $interface_config
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
  environment=${2:-test}

  echo "Installing a puppet server on '${hostname}' running in the environment: ${environment}"
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

if ! has_application vim ; then
  echo "Installing vim"
  if [[ $ID == 'centos' ]]; then
    $NOOP sudo yum install -y --quiet vim
  elif [[ $ID == 'ubuntu' ]]; then
    $NOOP sudo apt-get -y -qq install vim
  fi
fi

if ! has_application git ; then
  echo "Installing git"
  if [[ $ID == 'centos' ]]; then
    $NOOP sudo yum install -y --quiet git
  elif [[ $ID == 'ubuntu' ]]; then
    $NOOP sudo apt-get -y -qq install git
  fi
fi

if [[ $ID == 'centos' ]]; then
  if [[ -z $(rpm -qa | grep ruby) ]]; then
    echo "Installing Ruby"
    $NOOP sudo yum install -y --quiet ruby
  fi
elif [[ $ID == 'ubuntu' ]]; then
  if [[ -z $(dpkg-query -W -f='{Status}' ruby2.1 2>&1 | grep '\s+installed') ]]; then
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
    $NOOP sudo yum install -y --quiet puppet-server
  fi
elif [[ $ID == 'ubuntu' ]]; then
  if [[ -z $(dpkg-query -W -f='{Status}' puppetmaster 2>&1 | grep '\s+installed') ]]; then
    echo "Installing puppet server"
    if [[ $VERSION_ID == '14.04' ]]; then
      $NOOP sudo curl -sSL https://apt.puppetlabs.com/puppetlabs-release-trusty.deb -o /var/cache/apt/puppetlabs-release-trusty.deb
      $NOOP sudo dpkg -i /var/cache/apt/puppetlabs-release-trusty.deb
    elif [[ $VERSION_ID == '12.04' ]]; then
      $NOOP sudo curl -sSL https://apt.puppetlabs.com/puppetlabs-release-precise.deb -o /var/cache/apt/puppetlabs-release-precise.deb
      $NOOP sudo dpkg -i /var/cache/apt/puppetlabs-release-precise.deb
    fi
    $NOOP sudo apt-get -y -qq update
    $NOOP sudo apt-get -y -qq install passenger-dev puppetmaster-passenger
  fi
fi

  if [[ -z $(rpm -qa | grep puppetdb) ]] ; then
    # Updating puppet.conf for initial configuration
    if [[ $(md5sum /etc/puppet/puppet.conf | cut -d ' ' -f 1) != '73b7836a03de0dd8ece774a43627fef5' ]]; then
    (cat << EOD
[main]
  logdir = /var/log/puppet
  rundir = /var/run/puppet
  ssldir = \$vardir/ssl
  autoflush = true
  pluginsync = true

[master]
  certname = puppet
  dns_alt_names = puppet,puppet.localdomain,puppet.apac.inin.com,puppet.lab.apac.inin.com,puppet.demo.apac.inin.com,puppet.emea.inin.com 
  allow_duplicate_certs = true
  autosign = true

[agent]
  certname = puppetmaster
  server = puppet
  environment=${environment}
  classfile = \$vardir/classes.txt
  localconfig = \$vardir/localconfig
EOD
) | erb -T - | sudo tee /etc/puppet/puppet.conf > /dev/null
    fi

    bootstrap_dir="/etc/puppet/modules/bootstrap/manifests"
    [[ -d ${bootstrap_dir} ]] || $NOOP sudo mkdir -p ${bootstrap_dir}
    [[ $(stat -c %U ${bootstrap_dir}) == puppet ]] || $NOOP sudo chown puppet ${bootstrap_dir}
    [[ $(stat -c %G ${bootstrap_dir}) == puppet ]] || $NOOP sudo chgrp puppet ${bootstrap_dir}

    if [[ -z $(puppet module list --modulepath /etc/puppet/modules | grep puppetlabs-puppetdb) ]] ; then
      echo "Installing puppetdb module"
      sudo puppet module install puppetlabs/puppetdb --modulepath /etc/puppet/modules
    fi

    if [[ ! -r ${bootstrap_dir}/init.pp ]] ; then
      echo "Copying boostrap module"
    (cat << EOD
class bootstrap
{
  Exec { path => "/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" }
  File
  {
    owner => 'root',
    group => 'root',
    mode  => '0644',
  }

  class {'puppetdb':
    listen_address     => 'puppet',
    ssl_listen_address => 'puppet',
  } 

  class {'puppetdb::master::config':
    puppetdb_server => 'puppet',
  }
}
EOD
) | erb -T - | sudo tee ${bootstrap_dir}/init.pp > /dev/null
    fi

    if [[ -z $(sudo puppet master --configprint hostcert) ]] ; then
      # This should generate the server certificate as well
      echo "Generating SSL certificates"
      echo "  Starting Puppet Server"
      start_service puppetmaster
      echo -n "  Waiting for server certificate."
      i=0
      while [[ $i < 10 ]] ; do
        [[ -f /var/lib/puppet/ssl/certs/puppet.pem ]] && break
        sleep 1
        echo -n "."
        ((i++))
      done
      echo " "
      [[ $i == 10 ]] && (echo "Fatal Error: The Puppet server has not generated its certificate in a timely manner" && exit 1)

      $NOOP sudo puppet agent --test --waitforcert 30 --logdest /var/log/puppet/agent.log
      case $? in
        2)
          echo "  Successfully updated"
          ;;
        4)
          echo "  Failure while getting updated"
          exit 1
          ;;
        6)
          echo "  Partially updated"
          ;;
      esac
      echo "  Stopping Puppet Server"
      stop_service puppetmaster
    fi

    echo "Installing Puppet DB (This will take a few minutes)"
    sudo puppet apply --modulepath /etc/puppet/modules --logdest /var/log/puppetdb/install.log --debug -e 'include bootstrap'
  fi

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

  if [[ $ID == 'centos' ]]; then
    if [[ $VERSION_ID == "7" ]]; then
      # Running puppet master once to generate the CA
      #$NOOP systemctl start puppetmaster.service

      if [[ -z $(rpm -qa | grep httpd) ]]; then
        verbose "Installing Apache 2"
        [[ ! -z $(rpm -qa | grep httpd) ]]         || $NOOP sudo yum install -y httpd
        [[ ! -z $(rpm -qa | grep httpd-devel) ]]   || $NOOP sudo yum install -y httpd-devel
        [[ ! -z $(rpm -qa | grep mod_ssl) ]]       || $NOOP sudo yum install -y mod_ssl
        [[ ! -z $(rpm -qa | grep ruby-devel) ]]    || $NOOP sudo yum install -y ruby-devel
        [[ ! -z $(rpm -qa | grep gcc-c++) ]]       || $NOOP sudo yum install -y gcc-c++
        [[ ! -z $(rpm -qa | grep curl-devel) ]]    || $NOOP sudo yum install -y curl-devel
        [[ ! -z $(rpm -qa | grep zlib-devel) ]]    || $NOOP sudo yum install -y zlib-devel
        [[ ! -z $(rpm -qa | grep make) ]]          || $NOOP sudo yum install -y make
        [[ ! -z $(rpm -qa | grep automake) ]]      || $NOOP sudo yum install -y automake
        [[ ! -z $(rpm -qa | grep openssl-devel) ]] || $NOOP sudo yum install -y openssl-devel
      fi

      if [[ -z $(gem list --local | grep rack) ]] ; then
        echo "Installing gem rack"
        $NOOP sudo gem install --quiet --no-document rack
	[[ -d /usr/share/puppet/rack                      ]] || $NOOP sudo mkdir -p /usr/share/puppet/rack
	[[ -d /usr/share/puppet/rack/puppetmasterd        ]] || $NOOP sudo mkdir -p /usr/share/puppet/rack/puppetmasterd
	[[ -d /usr/share/puppet/rack/puppetmasterd/public ]] || $NOOP sudo mkdir -p /usr/share/puppet/rack/puppetmasterd/public
	[[ -d /usr/share/puppet/rack/puppetmasterd/tmp    ]] || $NOOP sudo mkdir -p /usr/share/puppet/rack/puppetmasterd/tmp
        $NOOP sudo chown -R puppet:puppet /usr/share/puppet/rack/puppetmasterd
      fi
      if [[ -z $(gem list --local | grep passenger) ]] ; then
        echo "Installing gem passenger"
        $NOOP sudo gem install --quiet --no-document passenger
	$NOOP sudo /usr/local/bin/passenger-install-apache2-module --auto
      fi

      (cat /etc/puppet/templates/mod_passenger.conf.erb) | erb -T - | sudo tee /etc/httpd/conf.modules.d/02-passenger.conf > /dev/null

      certificate=$(sudo puppet master --configprint hostcert)
      private_key=$(sudo puppet master --configprint hostprivkey)
      ca_certificate=$(sudo puppet master --configprint localcacert)
      ca_chain=$(sudo puppet master --configprint localcacert)
      ca_revocation=$(sudo puppet master --configprint cacrl)

      certname=puppet
      (echo "<% @hostname=\"${hostname}\"; @certificate=\"${certificate}\"; @private_key=\"${private_key}\"; @ca_certificate=\"${ca_certificate}\"; @ca_chain=\"${ca_chain}\"; @ca_revocation=\"${ca_revocation}\"; -%>" && cat /etc/puppet/templates/puppetmaster.conf.erb) | erb -T - | sudo tee /etc/httpd/conf.d/puppetmaster.conf > /dev/null

      if [[ ! -f /usr/share/puppet/rack/puppetmasterd/config.ru ]]; then
        verbose "Installing Rack config for Puppet master"
        $NOOP sudo cp /usr/share/puppet/ext/rack/config.ru /usr/share/puppet/rack/puppetmasterd
        $NOOP sudo chown puppet:puppet /usr/share/puppet/rack/puppetmasterd/config.ru
      fi
    fi
  fi

  #####
#  if [[ -z $(gem list --local | grep librarian-puppet) ]] ; then
#    echo "Installing librarian for puppet"
#    $NOOP sudo gem install --quiet --no-document librarian-puppet
#
#    echo "First run of librarian (This can some time...)"
#    $NOOP sudo sh -c "cd /etc/puppet && /usr/local/bin/librarian-puppet update --verbose 2>&1 | tee -a /var/log/puppet/librarian.log > /dev/null"
#  fi
  #####

  [[ -d /var/lib/hiera ]]                      || $NOOP sudo mkdir -p /var/lib/hiera
  [[ $(stat -c %U /var/lib/hiera) == puppet ]] || $NOOP sudo chown puppet /var/lib/hiera
  [[ $(stat -c %G /var/lib/hiera) == puppet ]] || $NOOP sudo chgrp puppet /var/lib/hiera
  [[ $(stat -c %a /var/lib/hiera) == 775    ]] || $NOOP sudo chmod 775 /var/lib/hiera
  [[ -r /etc/hiera.yaml ]]                     || $NOOP sudo ln -s /etc/puppet/hiera.yaml /etc/hiera.yaml

  [[ -d /var/cache/r10k ]]                      || $NOOP sudo mkdir -p /var/cache/r10k
  [[ $(stat -c %U /var/cache/r10k) == puppet ]] || $NOOP sudo chown puppet /var/cache/r10k
  [[ $(stat -c %G /var/cache/r10k) == puppet ]] || $NOOP sudo chgrp puppet /var/cache/r10k
  [[ $(stat -c %a /var/cache/r10k) == 775    ]] || $NOOP sudo chmod 775 /var/cache/r10k
  [[ -r /etc/r10k.yaml ]]                       || $NOOP sudo ln -s /etc/puppet/r10k.yaml /etc/r10k.yaml

  if [[ -z $(gem list --local | grep r10k) ]] ; then
    echo "Installing r10k for puppet"
    $NOOP sudo gem install --quiet --no-document r10k
  fi

  if [[ -d /var/lib/hiera/common ]]; then
    echo "Updating common hiera configuration via r10k"
    $NOOP sudo sh -c "/usr/local/bin/r10k -v debug deploy environment common 2>&1 | tee -a /var/log/puppet/r10k-common.log"
  else
    echo "Installing common hiera configuration via r10k"
    $NOOP sudo sh -c "/usr/local/bin/r10k -v debug deploy environment common 2>&1 | tee -a /var/log/puppet/r10k-common.log"
  fi

  if [[ -d /var/lib/hiera/${environment} ]]; then
    echo "Updating ${environment} environment via r10k"
    $NOOP sudo sh -c "/usr/local/bin/r10k -v debug deploy environment ${environment} --puppetfile 2>&1 | tee -a /var/log/puppet/r10k-${environment}.log"
  else
    echo "Installing ${environment} environment via r10k"
    $NOOP sudo sh -c "/usr/local/bin/r10k -v debug deploy environment ${environment} --puppetfile 2>&1 | tee -a /var/log/puppet/r10k-${environment}.log"
  fi

#  $NOOP sudo chown -R puppet:puppet /var/lib/puppet/clientbucket /var/lib/puppet/client_data /var/lib/puppet/client_yaml /var/lib/puppet/facts.d /var/lib/puppet/lib

  disable_service puppetmaster
  enable_service  httpd
  stop_service    puppetmaster
  start_service   httpd

  verbose "Enabling and Starting Puppet agent"
  #sudo puppet resource service puppet ensure=running enable=true
  enable_service  puppet
  start_service   puppet
  #verbose "Adding a cron job for the puppet agent"
  #sudo puppet resource cron puppet-agent ensure=present user=root minute=30 command='/usr/bin/puppet agent --onetime --no-daemonize --splay'

  # Open the firewall: ssh: 22, puppet mater: 8140, apache: 80/443, dashboard: 3000
  verbose "Configuring the firewall"
  if [[ $ID == 'centos' ]]; then
    start_service firewalld
    $NOOP sudo firewall-cmd --zone=public --add-port=8140/tcp --permanent
    $NOOP sudo firewall-cmd --reload
    enable_service firewalld
  elif [[ $ID == 'ubuntu' ]]; then
    $NOOP sudo ufw allow 22
    $NOOP sudo ufw allow 3000
    $NOOP sudo ufw allow 8140
    $NOOP sudo ufw --force enable
  fi
# TODO: Should we use jenkins too?
} # }}}

main
