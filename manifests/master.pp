# Class: puppet::master
#
# This class installs and configures a Puppet master
#
# Parameters:
#   [*modulepath*]            - The modulepath configuration value used in
#                               puppet.conf
#   [*confdir*]               - The confdir configuration value in puppet.conf
#   [*manifest*]              - The manifest configuration value in puppet.conf
#   [*templatedir*]           - The path to templates
#   [*reporting*]             - Turn reporting on or off
#   [*storeconfigs*]          - Boolean determining whether storeconfigs is
#                               to be enabled.
#   [*storeconfigs_dbadapter*] - The database adapter to use with storeconfigs
#   [*storeconfigs_dbuser*]   - The database username used with storeconfigs
#   [*storeconfigs_dbpassword*] - The database password used with storeconfigs
#   [*storeconfigs_dbserver*]   - Fqdn of the storeconfigs database server
#   [*storeconfigs_dbsocket*]   - The path to the mysql socket file
#   [*install_mysql_pkgs*]      - Boolean determining whether mysql and related
#                                 devel packages should be installed.
#   [*certname*]              - The certname configuration value in puppet.conf
#   [*autosign*]              - The autosign configuration value in puppet.conf
#   [*dashboard_port*]          - The port on which puppet-dashboard should run
#   [*puppet_passenger*]      - Boolean value to determine whether puppet is
#                               to be run with Passenger
#   [*puppet_site*]           - The VirtualHost value used in the apache vhost
#                               configuration file when Passenger is enabled
#   [*puppet_docroot*]        - The DocumentRoot value used in the apache vhost
#                               configuration file when Passenger is enabled
#   [*puppet_vardir*]         - The path to the puppet vardir
#   [*puppet_passenger_port*] - The port on which puppet is listening when
#                               Passenger is enabled
#   [*puppet_master_package*]   - The name of the puppet master package
#   [*package_provider*]        - The provider used for package installation
#   [*version*]               - The value of the ensure parameter for the
#                               puppet master and agent packages
#
# Actions:
#
# Requires:
#
#  Class['concat']
#  Class['stdlib']
#  Class['concat::setup']
#  Class['mysql'] (conditionally)
#
# Sample Usage:
#
#  $modulepath = [
#    "/etc/puppet/modules/site",
#    "/etc/puppet/modules/dist",
#  ]
#
#  class { "puppet::master":
#    modulepath => inline_template("<%= modulepath.join(':') %>"),
#    dbadapter  => "mysql",
#    dbuser     => "puppet",
#    dbpassword => "password"
#    dbsocket   => "/var/run/mysqld/mysqld.sock",
#  }
#
class puppet::master (
  $modulepath = $::puppet::params::modulepath,
  $confdir = $::puppet::params::confdir,
  $puppet_conf = $::puppet::params::puppet_conf,
  $manifest = $::puppet::params::manifest,
  $templatedir = $::puppet::params::templatedir,
  $reporting = true,
  $storeconfigs = false,
  $storeconfigs_dbadapter = $::puppet::params::storeconfigs_dbadapter,
  $storeconfigs_dbuser = $::puppet::params::storeconfigs_dbuser,
  $storeconfigs_dbpassword = $::puppet::params::storeconfigs_dbpassword,
  $storeconfigs_dbserver = $::puppet::params::storeconfigs_dbserver,
  $storeconfigs_dbsocket = $::puppet::params::storeconfigs_dbsocket,
  $install_mysql_pkgs = $::puppet::params::puppet_storeconfigs_packages,
  $certname = $::fqdn,
  $autosign = false,
  $dashboard_port = 3000,
  $puppet_passenger = false,
  $puppet_site = $::puppet::params::puppet_site,
  $puppet_docroot = $::puppet::params::puppet_docroot,
  $puppet_vardir = $::puppet::params::puppet_vardir,
  $puppet_passenger_port = false,
  $puppet_master_package = $::puppet::params::puppet_master_package,
  $package_provider = undef,
  $puppet_master_service = $::puppet::params::puppet_master_service,
  $version = 'present',
  $paternalistic = true,

) inherits puppet::params {

  include concat::setup

  File {
    require => Package[$puppet_master_package],
    owner   => 'puppet',
    group   => 'puppet',
  }

  if $storeconfigs {
    class { 'puppet::storeconfigs':
      puppet_conf   => $puppet_conf,
      dbadapter     => $storeconfigs_dbadapter,
      dbuser        => $storeconfigs_dbuser,
      dbpassword    => $storeconfigs_dbpassword,
      dbserver      => $storeconfigs_dbserver,
      dbsocket      => $storeconfigs_dbsocket,
      paternalistic => $paternalistic,
    }
  }

  if ! defined(Package[$puppet_master_package]) {
    package { $puppet_master_package:
      ensure   => $version,
      provider => $package_provider,
    }
  }

  if $puppet_passenger {
    $service_notify  = Service['httpd']
    $service_require = [Package[$puppet_master_package], Class['passenger']]

    exec { "Certificate_Check":
      command   => "puppet cert --generate ${certname} --trace",
      unless    => "/bin/ls ${puppet_ssldir}/certs/${certname}.pem",
      path      => "/usr/bin:/usr/local/bin",
      before    => Class['::passenger'],
      require   => Package[$puppet_master_package],
      logoutput => on_failure,
    }

    if ! defined(Class['passenger']) {
      class { '::passenger': }
    }

    apache::vhost { "puppet-${puppet_site}":
      servername => $puppet_site,
      port       => $puppet_passenger_port,
      priority   => '40',
      docroot    => $puppet_docroot,
      template   => 'puppet/apache2.conf.erb',
      require    => [ File["${confdir}/rack/config.ru"], File[$puppet_conf] ],
      ssl        => true,
    }

    file { "${confdir}/rack":
      ensure => directory,
      mode   => '0755',
    }

    file { "${confdir}/rack/config.ru":
      ensure => present,
      source => $puppet::params::rack_config_source,
      mode   => '0644',
      require => Package[$puppet_master_package],
    }
  } else {

    $service_require = Package[$puppet_master_package]
    $service_notify = Exec['puppet_master_start']

    exec { 'puppet_master_start':
      command   => '/usr/bin/nohup puppet master &',
      refresh   => '/usr/bin/pkill puppet && /usr/bin/nohup puppet master &',
      unless    => "/bin/ps -ef | grep -v grep | /bin/grep 'puppet master'",
      require   => File[$puppet_conf],
      subscribe => Package[$puppet_master_package],
    }
  }

  concat::fragment { 'puppet.conf-master':
    order   => '05',
    target  => $puppet_conf,
    content => template("puppet/puppet.conf-master.erb"),
    notify  => $service_notify,
  }

  Concat<| title == $puppet_conf |> {
    require => $service_require,
    notify  +> $service_notify,
  }

  file { $puppet_vardir:
    ensure       => directory,
    recurse      => true,
    recurselimit => '1',
    notify       => $service_notify,
  }

  File [$confdir] {
    require +> Package[$puppet_master_package],
    notify  +> $service_notify
  }

}

