# @summary Nginx as a reverse proxy in front of the demo app.
#
# The Puppet version of the Ansible role ansible/roles/nginx: it writes the same
# configuration, and `make verify` runs the same checks against both.
#
# @param server_names
#   Names the site answers to.
# @param trusted_proxies
#   Load balancers whose X-Forwarded-For header is trusted, so the logs show the client.
# @param served_by
#   Name sent back in the X-Served-By header.
# @param app_port
#   Port of the demo app on localhost.
# @param access_log
#   Access log, in the "combined" format that scripts/log-triage.sh reads.
class demo_web (
  Array[String[1], 1] $server_names,
  Array[String[1]] $trusted_proxies,
  String[1] $served_by,
  Integer[1, 65535] $app_port,
  Pattern[/^\//] $access_log,
) {
  package { 'nginx':
    ensure => installed,
  }

  file { '/etc/nginx/conf.d/hardening.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet (class demo_web)\nserver_tokens off;\n",
    require => Package['nginx'],
    notify  => Exec['nginx-configtest'],
  }

  file { '/etc/nginx/sites-available/demo-app':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('demo_web/site.conf.epp', {
      'server_names'    => $server_names,
      'trusted_proxies' => $trusted_proxies,
      'served_by'       => $served_by,
      'app_port'        => $app_port,
      'access_log'      => $access_log,
    }),
    require => Package['nginx'],
    notify  => Exec['nginx-configtest'],
  }

  file { '/etc/nginx/sites-enabled/demo-app':
    ensure => link,
    target => '/etc/nginx/sites-available/demo-app',
    notify => Exec['nginx-configtest'],
  }

  file { '/etc/nginx/sites-enabled/default':
    ensure  => absent,
    require => Package['nginx'],
    notify  => Exec['nginx-configtest'],
  }

  # Test the whole configuration before reloading. If the test fails, Puppet skips the
  # reload that depends on it, so the running Nginx keeps its last good configuration.
  exec { 'nginx-configtest':
    command     => '/usr/sbin/nginx -t',
    refreshonly => true,
    notify      => Service['nginx'],
  }

  service { 'nginx':
    ensure  => running,
    enable  => true,
    restart => '/usr/bin/systemctl reload nginx',
    require => Package['nginx'],
  }
}
