#!/bin/bash

set -euxo pipefail

# Configure repository
cat > /etc/yum.repos.d/mongodb-org-9.0.repo << 'EOF'
[mongodb-org-9.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/10/mongodb-org/9.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF

sudo yum install -y mongodb-org

sed -i 's/^  bindIp: 127.0.0.1/  bindIp: 0.0.0.0/' /etc/mongod.conf

sudo systemctl enable --now mongod