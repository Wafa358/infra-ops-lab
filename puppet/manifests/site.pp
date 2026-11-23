# Masterless Puppet: each web VM applies this file with `puppet apply`, every 30 minutes
# (see ansible/roles/puppet_nginx). Class parameters come from Hiera.
node default {
  include demo_web
}
