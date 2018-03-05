#!/bin/bash

set -e

echo "Set var file..."
mkdir -p /etc/ansible/host_vars
cat << EOF > /etc/ansible/host_vars/localhost
ecs_clustername: ${ecs_clustername}
env: ${env}
component_id: ${component_id}
http_proxy:
  endpoint: ${proxy}
EOF

echo "Run ansible for local configuration..."
cd /etc/ansible/playbooks
ansible-playbook provision.yml