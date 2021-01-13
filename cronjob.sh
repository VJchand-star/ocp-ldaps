oc --user=admin process --local \
  -f openshift-management/jobs/cronjob-ldap-group-sync-secure.yml \
  -p NAMESPACE='openshift-cluster-ops' \
  -p LDAP_URL=ldaps://${LDAPSVR}.${DOMAIN}.${COM}:636 \
  -p LDAP_BIND_DN=uid=${BINDUSER},cn=users,cn=accounts,dc=${DOMAIN},dc=${COM} \
  -p LDAP_BIND_PASSWORD='${BINDPASSWORD}' \
  -p LDAP_CA_CERT="$(cat ${LDAP-CA.CRT})" \
  -p LDAP_GROUP_UID_ATTRIBUTE='dn' \
  -p LDAP_GROUPS_FILTER='(objectClass=groupofnames)' \
  -p LDAP_GROUPS_SEARCH_BASE='cn=groups,cn=accounts,dc=${DOMAIN},dc=${COM}' \
  -p LDAP_GROUPS_WHITELIST="$(cat ldap-whitelist-groups)" \
  -p LDAP_USERS_SEARCH_BASE='cn=users,cn=accounts,dc=${DOMAIN},dc=${COM}' \
  -p SCHEDULE='*/15 * * * *' \
  | oc --user=admin apply -f -
