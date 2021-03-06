# Configure the neutron server to use the OVS plugin.
# This configures the plugin for the API server, but does nothing
# about configuring the agents that must also run and share a config
# file with the OVS plugin if both are on the same machine.
#
# === Parameters
#
# [*sql_idle_timeout*]
#   (optional) Timeout for SQL to reap connetions.
#   Defaults to '3600'.
#
class neutron::plugins::ovs (
  $package_ensure       = 'present',
  $sql_connection       = 'sqlite:////var/lib/neutron/ovs.sqlite',
  $sql_max_retries      = 10,
  $sql_idle_timeout     = '3600',
  $reconnect_interval   = 2,
  $tenant_network_type  = 'vlan',
  # NB: don't need tunnel ID range when using VLANs,
  # *but* you do need the network vlan range regardless of type,
  # because the list of networks there is still important
  # even if the ranges aren't specified
  # if type is vlan or flat, a default of physnet1:1000:2000 is used
  # otherwise this will not be set by default.
  $network_vlan_ranges  = undef,
  $tunnel_id_ranges     = '1:1000'
) {

  include neutron::params

  Package['neutron'] -> Package['neutron-plugin-ovs']
  Package['neutron-plugin-ovs'] -> Neutron_plugin_ovs<||>
  Neutron_plugin_ovs<||> ~> Service<| title == 'neutron-server' |>
  Package['neutron-plugin-ovs'] -> Service<| title == 'neutron-server' |>

  validate_re($sql_connection, '(sqlite|mysql|postgresql):\/\/(\S+:\S+@\S+\/\S+)?')

  case $sql_connection {
    /mysql:\/\/\S+:\S+@\S+\/\S+/: {
      require 'mysql::python'
    }
    /postgresql:\/\/\S+:\S+@\S+\/\S+/: {
      $backend_package = 'python-psycopg2'
    }
    /sqlite:\/\//: {
      $backend_package = 'python-pysqlite2'
    }
    default: {
      fail("Invalid sql connection: ${sql_connection}")
    }
  }

  if ! defined(Package['neutron-plugin-ovs']) {
    package { 'neutron-plugin-ovs':
      ensure  => $package_ensure,
      name    => $::neutron::params::ovs_server_package,
    }
  }

  neutron_plugin_ovs {
    'DATABASE/sql_connection':      value => $sql_connection;
    'DATABASE/sql_max_retries':     value => $sql_max_retries;
    'DATABASE/sql_idle_timeout':    value => $sql_idle_timeout;
    'DATABASE/reconnect_interval':  value => $reconnect_interval;
    'OVS/tenant_network_type':      value => $tenant_network_type;
  }

  if($tenant_network_type == 'gre') {
    neutron_plugin_ovs {
      # this is set by the plugin and the agent - since the plugin node has the agent installed
      # we rely on it setting it.
      # TODO(ijw): do something with a virtualised node
      # 'OVS/enable_tunneling':   value => 'True';
      'OVS/tunnel_id_ranges':   value => $tunnel_id_ranges;
    }
  }

  # If the user hasn't specified vlan_ranges, fail for the modes where
  # it is required, otherwise keep it absent
  if ($tenant_network_type == 'vlan') or ($tenant_network_type == 'flat') {
    if ! $network_vlan_ranges {
      fail('When using the vlan network type, network_vlan_ranges is required')
    }
  } else {
    if ! $network_vlan_ranges {
      neutron_plugin_ovs { 'OVS/network_vlan_ranges': ensure => absent }
    }
  }

  # This might be set by the user for the gre case where
  # provider networks are in use
  if $network_vlan_ranges {
    neutron_plugin_ovs {
      'OVS/network_vlan_ranges': value => $network_vlan_ranges
    }
  }

  if $::osfamily == 'Redhat' {
    file {'/etc/neutron/plugin.ini':
      ensure  => link,
      target  => '/etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini',
      require => Package['neutron-plugin-ovs']
    }
  }
}
