#!/bin/bash

# Update and install required packages
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y slapd ldap-utils

# Set admin password and domain
ADMIN_PASS="admin"
DOMAIN="example.com"
BASE_DN="dc=example,dc=com"

# Reconfigure slapd with preset options
sudo debconf-set-selections <<EOF
slapd slapd/password1 password $ADMIN_PASS
slapd slapd/password2 password $ADMIN_PASS
slapd slapd/domain string $DOMAIN
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF

sudo dpkg-reconfigure -f noninteractive slapd

# Create temporary LDIF file for users
cat << EOF > /tmp/users.ldif
# Organization Unit for Users
dn: ou=users,$BASE_DN
objectClass: organizationalUnit
ou: users

# User test1
dn: uid=test1,ou=users,$BASE_DN
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: test1
sn: Test
givenName: User1
cn: Test User1
displayName: Test User1
uidNumber: 10000
gidNumber: 10000
userPassword: {SSHA}$(slappasswd -s "1234567890")
loginShell: /bin/bash
homeDirectory: /home/test1

# User test2
dn: uid=test2,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: test2
sn: Test
givenName: User2
cn: Test User2
displayName: Test User2
uidNumber: 10001
gidNumber: 10001
userPassword: {SSHA}$(slappasswd -s "1234567890")
loginShell: /bin/bash
homeDirectory: /home/test2
EOF

# Add users to LDAP
ldapadd -x -D "cn=admin,$BASE_DN" -w $ADMIN_PASS -f /tmp/users.ldif

# Clean up
rm /tmp/users.ldif

# Verify service is running
sudo systemctl restart slapd
sudo systemctl status slapd

# Test LDAP connection
ldapsearch -x -b "$BASE_DN" -H ldap://localhost

echo "LDAP setup complete. Users test1 and test2 created with password: 1234567890"