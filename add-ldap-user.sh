#!/bin/bash

# Prompt for username and password
read -p "Enter username: " username
read -s -p "Enter password: " password
echo

# Create temporary LDIF file
cat > /tmp/new_user.ldif << EOF
dn: uid=$username,ou=users,dc=example,dc=com
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
cn: Test $username
sn: $username
uid: $username
userPassword: $(slappasswd -s "$password")
EOF

# Add user to LDAP
ldapadd -x -D "cn=admin,dc=example,dc=com" -w admin -f /tmp/new_user.ldif

# Clean up
rm /tmp/new_user.ldif

# Verify user was added
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=example,dc=com" -w admin -b "dc=example,dc=com" "(uid=$username)"