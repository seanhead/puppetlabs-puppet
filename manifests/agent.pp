# Class: puppet::agent
#
# This class installs and configures the puppet agent
#
# Parameters:
#
# Actions:
#
# Requires:
#
# Sample Usage:
#
class puppet::agent(
  $puppet_server,
  $environment = $::puppet::params::environment,
  $puppet_defaults = $::puppet::params::puppet_defaults,
  $puppet_agent_service = $::puppet::params::puppet_agent_service,
  $puppet_agent_name = $::puppet::params::puppet_agent_name,
  $puppet_conf = $::puppet::params::puppet_conf,
  $package_provider = undef,
  $reporting = true,
  $version = 'present'
) inherits puppet::params {

  if $::kernel == "Linux" {
    file { $puppet_defaults:
      mode   => '0644',
      owner  => 'root',
      group  => 'root',
      source => "puppet:///modules/puppet/${puppet_defaults}",
    }
  }

  if ! defined(Package[$puppet_agent_name]) {
    package { $puppet_agent_name:
      ensure   => $version,
      provider => $package_provider,
    }
  }

  if $package_provider == 'gem' {
    $service_notify = Exec['puppet_agent_start']

    exec { 'puppet_agent_start':
      command   => '/usr/bin/nohup puppet agent &',
      refresh   => '/usr/bin/pkill puppet && /usr/bin/nohup puppet agent &',
      unless    => "/bin/ps -ef | grep -v grep | /bin/grep 'puppet agent'",
      require   => File[$puppet_conf],
      subscribe => Package[$puppet_agent_name],
    }
  } else {
    $service_notify = Service[$puppet_agent_service]

    service { $puppet_agent_service:
      ensure     => running,
      enable     => true,
      hasstatus  => true,
      hasrestart => true,
      require    => File[$puppet_conf],
      subscribe  => Package[$puppet_agent_name],
    }
  }

  File [$confdir] {
    require +> Package[$puppet_agent_name],
    notify  +> $service_notify
  }

  Concat<| title == $puppet_conf |> {
    require => Package['puppet'],
    notify  +> $puppet::agent::service_notify,
  }

  concat::fragment { 'puppet.conf-agent':
    order   => '00',
    target  => $puppet_conf,
    content => template("puppet/puppet.conf-agent.erb"),
  }
}
