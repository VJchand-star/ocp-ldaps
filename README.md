# Configuring LDAP/s with OpenShift

In this example, I will be configuring access to OpenShift 4.x against Red Hat Identity Management [IdM]. The process will be very similar to many LDAP systems; however, you'll to discover your own values with ldapsearch or some tool like JXplorer (http://www.jxplorer.org).

Before we begin, let's take a look at our ocp-ldaps.yaml file :
```
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: Local Accounts
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd
  - name: RedCloud IdM
    mappingMethod: claim
    type: LDAP
    ldap:
      attributes:
        id:
        - dn
        email:
        - mail
        name:
        - cn
        preferredUsername:
        - uid
      bindDN: "uid=ocpadmin,cn=users,cn=accounts,dc=redcloud,dc=land"
      bindPassword:
        name: ldap-secret
      insecure: false
      ca:
        name: ca-configmap
      url: "ldaps://idm.redcloud.land:636/cn=users,cn=accounts,dc=redcloud,dc=land?uid"
```
You can have multiple identity providers, please note that if you 'replace' this configuration it will overwrite whatever is already there. For account safetly, ensure you have all of your identity providers listed... here you'll see that I have included my local accounts using htpasswd.

The 'bindDN' is the account which will adminster the ldap/s connection; this can be a read-only account since we'll administer account names and groups assignments from IdM (Ldap).

The 'bindPassword' is stored as a secret and is the litteral password for the bindDN account.

In this setup, I'll be installing the IdM certificate to enable secure access between IdM & OpenShift.
```
      insecure: false
      ca:
        name: ca-configmap
```

1. Creating the bindPassword \
` oc create secret generic -n openshift-config ldap-secret --from-literal=bindPassword='SoMePaSsWoRd!'`

2. Store the IdM CA : I do this even if it's the same CA as my OpenShift Cluster \
` oc create configmap ca-configmap --from-file=ca.crt=idm-ca.crt -n openshift-config `

3. Install the Ldap config into OpenShift \
` oc replace -f ocp-ldaps.yaml `

Now we should be plugged in, but we haven't pulled in users or groups yet. For this part, we'll need to use a "LDAPSyncConfig"... let's have a look at our ldap-sync.yaml file

```
kind: LDAPSyncConfig
apiVersion: v1
url: "ldaps://idm.redcloud.land:636"
bindDN: "uid=ocpadmin,cn=users,cn=accounts,dc=redcloud,dc=land"
bindPassword:
  name: ldap-secret 
ca:
  name: ca-configmap
insecure: false
rfc2307:
  groupsQuery:
    baseDN: "cn=groups,cn=accounts,dc=redcloud,dc=land"
    scope: sub
    derefAliases: never
    filter: (objectClass=groupofnames)
    pageSize: 0
    timeout: 0
  groupUIDAttribute: dn
  groupNameAttributes: [ cn ]
  groupMembershipAttributes: [ member ]
  usersQuery:
    baseDN: "cn=users,cn=accounts,dc=redcloud,dc=land"
    scope: sub
    derefAliases: never
    pageSize: 0
  userUIDAttribute: dn
  userNameAttributes: [ uid ]
```
We can test this sync before committing it, once we add the flag --confirm it will be committed.

1. Create a 'whitelist' of the groups you want to sync into OpenShift and save it in a file, ex: ldap-whitelist-groups
```
cn=ocp-admins,cn=groups,cn=accounts,dc=redcloud,dc=land
cn=ocp-users,cn=groups,cn=accounts,dc=redcloud,dc=land
cn=ocp-developers,cn=groups,cn=accounts,dc=redcloud,dc=land
cn=ocp-production,cn=groups,cn=accounts,dc=redcloud,dc=land
```
2. Test the LDAPSyncConfig \
` oc adm groups sync --sync-config=ldap-sync.yaml --whitelist=ldap-whitelist-groups `

    NOTE: If we have pulled groups, your golden! If not, then you'll need to investigate further...

3. Commit the LDAPSyncConfig \
` oc adm groups sync --sync-config=ldap-sync.yaml --whitelist=ldap-whitelist-groups --confirm `

From here you will have to add users to groups and manage their access using roles, either in the UI or via CLI (oc adm policy add-cluster-role-to-group $group $group-name).

Things change... so let's make sure we're constantly up to date by running a stored cronjob.

1. Create a namespace for the Ldap cron job \
` oc adm new-project openshift-cluster-ops `

2. Run this shell script (with your values) to store the crontab *ignore any warnings you may see\
```
oc --user=admin process --local \
  -f openshift-management/jobs/cronjob-ldap-group-sync-secure.yml \
  -p NAMESPACE='openshift-cluster-ops' \
  -p LDAP_URL=ldaps://idm.redcloud.land:636 \
  -p LDAP_BIND_DN=uid=ocpadmin,cn=users,cn=accounts,dc=redcloud,dc=land \
  -p LDAP_BIND_PASSWORD='SoMePaSsWoRd!' \
  -p LDAP_CA_CERT="$(cat idm-ca.crt)" \
  -p LDAP_GROUP_UID_ATTRIBUTE='dn' \
  -p LDAP_GROUPS_FILTER='(objectClass=groupofnames)' \
  -p LDAP_GROUPS_SEARCH_BASE='cn=groups,cn=accounts,dc=redcloud,dc=land' \
  -p LDAP_GROUPS_WHITELIST="$(cat ldap-whitelist-groups)" \
  -p LDAP_USERS_SEARCH_BASE='cn=users,cn=accounts,dc=redcloud,dc=land' \
  -p SCHEDULE='*/15 * * * *' \
  | oc --user=admin apply -f -
```

That's it! You now have Ldap access provisioned to OpenShift and it will update itself every 15mins.
