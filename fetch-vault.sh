#!/bin/bash

# There are many required environment variables:
# * VAULT_ADDR: The Vault address.
# * VAULT_APPID: The Vault AppRole Role ID
# * VAULT_MOUNT: The path where the Key-Value Secrets Engine is mounted
# * VAULT_BASE: The base path for Bookstack data
#
# * BOOKSTACK_SECRET_SAML_CERT: The path where to write the Bookstack SAML Cert
# * BOOKSTACK_SECRET_SAML_KEY: The path where to write the Bookstack SAML Key
# * BOOKSTACK_SECRET_DB_ROOT_PASSWORD: The path where to write the Bookstack
#   DB's root password.
# * BOOKSTACK_SECRET_DB_BOOKSTACK_PASSWORD: The path where to write the
#   Bookstack DB's password for the Bookstack user.

# The AppRole's Secret ID may either be entered to standard input (when
# prompted), or via the VAULT_SECRET environment variable.

set -eu
set -o pipefail

# Show the Vault environment variables
echo "Using Vault server address ${VAULT_ADDR}" >&2
echo "Using Vault AppRole Role ID ${VAULT_APPID}" >&2
echo "Using Vault Key-Value Secrets Engine mounted at ${VAULT_MOUNT}" >&2
echo "Using base path ${VAULT_BASE}" >&2

# Get the Vault secret
if [ ! "${VAULT_SECRET:-x}" = "x" ]; then
	echo "Using Vault secret passed via the environment" >&2
else
	echo
	echo -n "Please enter the Vault AppRole's Secret ID: "
	read VAULT_SECRET
	echo -n "Use Secret ID ${VAULT_SECRET} [y/n]? "
	read yn
	if [ ! $yn = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

# Remove the persisted Vault token, if there is one.
if [ -f ~/.vault-token ]; then
	rm -f ~/.vault-token
fi

# Get a Vault token
VAULT_CRED=$(vault write -force -field=token auth/approle/login role_id=${VAULT_APPID} secret_id=${VAULT_SECRET})
vault login -no-print -method=token ${VAULT_CRED}


# Get our Vault data.
echo "Will write SAML cert to ${BOOKSTACK_SECRET_SAML_CERT}" >&2
echo "Will write SAML key to ${BOOKSTACK_SECRET_SAML_KEY}" >&2
vault kv get -mount=${VAULT_MOUNT} -field=cert "${VAULT_BASE}/saml" > ${BOOKSTACK_SECRET_SAML_CERT}
vault kv get -mount=${VAULT_MOUNT} -field=key "${VAULT_BASE}/saml" > ${BOOKSTACK_SECRET_SAML_KEY}
echo "Will write MariaDB root password to ${BOOKSTACK_SECRET_DB_ROOT_PASSWORD}" >&2
echo "Will write Bookstack DB password to ${BOOKSTACK_SECRET_DB_BOOKSTACK_PASSWORD}" >&2
vault kv get -mount=${VAULT_MOUNT} -field=root "${VAULT_BASE}/db" > ${BOOKSTACK_SECRET_DB_ROOT_PASSWORD}
vault kv get -mount=${VAULT_MOUNT} -field=bookstack "${VAULT_BASE}/db" > ${BOOKSTACK_SECRET_DB_BOOKSTACK_PASSWORD}

# Finally, remove the persisted Vault token and exit!
if [ -f ~/.vault-token ]; then
	rm -f ~/.vault-token
fi
exit 0
