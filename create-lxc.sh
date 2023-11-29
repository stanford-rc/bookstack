#!/bin/bash
# vim: ts=4 sw=4 noet

# This script will make a Bookstack LXC container!
# It asks a number of questions, and then kicks off an LXC container creation,
# which does some of the basic setup needed for a Bookstack container.

# This script asks for the following info, which can be provided through
# setting the following environment variables:
# * The server name (BOOKSTACK_NAME)
# * Acceptance of the Let's Encrypt ToS (set ACCEPT_LETS_ENCRYPT_TOS to "yes")
# * An email address to use for Let's Encrypt notifications # (LETS_ENCRYPT_EMAIL)
# * The Git repo URL (HTTPS only) and branch/tag/commit (GIT_REPO for the URL;
#   GIT_COMMIT for the commit hash).
# * A Vault Address (VAULT_ADDR)
# * A Vault AppRole ID (VAULT_APPID)
# * The path to the Key-Value Secrets Engine (VAULT_MOUNT)
# * The base path where Bookstack Secrets may be found in Vault (VAULT_BASE)

# The LXC container is set up as follows:
# * 2 cores and 8 GiB memory
# * Ubuntu 22.04 LTS
# * Nesting (Docker in Docker) is enabled
# * The `mknod` and `setxattr` syscalls are allowed.
# * The Hashicorp APT repo is added.
# * `apt-get update` and `apt-get upgrade` are run.
# * Vault (client), Docker, Docker Compose, and Git are installed.
# * The repo is checked out.
# * Environment variables are populated.

# After the LXC container is set up, the user is given the MAC address, and
# told what to do next.

set -eu
set -o pipefail

if [ ! "${BOOKSTACK_NAME:-x}" = "x" ]; then
	echo "Using Bookstack name ${BOOKSTACK_NAME}" >&2
else
	echo -n "What will be the name for this Bookstack server? "
	read BOOKSTACK_NAME
	echo -n "So, this will be ${BOOKSTACK_NAME}.stanford.edu [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ "${ACCEPT_LETS_ENCRYPT_TOS:-no}" = "yes" ]; then
	echo "Accepted Let's Encrypt ToS" >&2
else
	echo
	echo "The Bookstack server will use Let's Encrypt for its TLS certificate."
	echo "Let's Encrypt is governed by the ToS at https://letsencrypt.org/repository/"
	echo -n "Do you agree to the Let's Encrypt ToS [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${LETS_ENCRYPT_EMAIL:-x}" = "x" ]; then
	echo "Using Let's Encrypt contact email ${LETS_ENCRYPT_EMAIL}" >&2
else
	echo
	echo "When there's a problem with our cert, Let's Encrypt will email us."
	echo -n "What email should Let's Encrypt use for notifications? "
	read LETS_ENCRYPT_EMAIL
	echo -n "Use ${LETS_ENCRYPT_EMAIL} for notifications [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${VAULT_ADDR:-x}" = "x" ]; then
	echo "Using Vault Address ${VAULT_ADDR}" >&2
else
	echo
	echo "Secrets relating to Bookstack are in Vault."
	echo -n "What is the address of the Vault server? "
	read VAULT_ADDR
	echo -n "Use ${VAULT_ADDR} as the Vault server [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${VAULT_APPID:-x}" = "x" ]; then
	echo "Using Vault AppRole ID ${VAULT_APPID}" >&2
else
	echo
	echo "A Vault AppRole is used for auth."
	echo -n "What is the App ID for the AppRole? "
	read VAULT_APPID
	echo -n "Use ${VAULT_APPID} as the AppRole ID [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${VAULT_MOUNT:-x}" = "x" ]; then
	echo "Using Vault Key-Value Secrets Engine mount point ${VAULT_MOUNT}" >&2
else
	echo
	echo "Secrets are stored in the Key-Value Secrets Engine."
	echo -n "Where is the Secrets Engine mounted? "
	read VAULT_MOUNT
	echo -n "Use ${VAULT_MOUNT} as the Key-Value Secrets Engine mount point [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${VAULT_BASE:-x}" = "x" ]; then
	echo "Using base path for Vault Secrets ${VAULT_BASE}" >&2
else
	echo
	echo -n "In Vault, what base path should be used to find secrets? "
	read VAULT_BASE
	echo -n "Use ${VAULT_BASE} as the base path for secrets in Vault [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${GIT_REPO:-x}" = "x" ]; then
	echo "Using Git Repo URL ${GIT_REPO}" >&2
else
	echo
	echo "The LXC creation process will clone the repo with our scripts."
	echo -n "What's the HTTPS URL [https://github.com/stanford-rc/bookstack.git]? "
	read GIT_REPO
	GIT_REPO=${GIT_REPO:=https://github.com/stanford-rc/bookstack.git}
	echo -n "Use repo ${GIT_REPO} [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ ! "${GIT_COMMIT:-x}" = "x" ]; then
	echo "Using Git commit ID/tag/branch ${GIT_COMMIT}" >&2
else
	echo
	echo "The Git repo can be checked out to a specific commit, branch, or tag."
	echo -n "Enter a commit ID, branch name, or tag name [main]: "
	read GIT_COMMIT
	GIT_COMMIT=${GIT_COMMIT:=main}
	echo -n "Check out ${GIT_REPO} to ${GIT_COMMIT} [y/n]? "
	read yn
	if [ ! ${yn} = y ]; then
		echo 'Exiting'
		exit 1
	fi
fi

if [ "${PARSABLE:-no}" = "yes" ]; then
	LXC_FLAGS="--quiet"
else
	echo
	echo "Creating LXD container ${BOOKSTACK_NAME}..."
	LXC_FLAGS="--verbose"
fi
lxc ${LXC_FLAGS} init ubuntu:22.04 ${BOOKSTACK_NAME} <<EOF
---
config:
  limits.cpu: 2
  limits.memory: 8GiB
  security.nesting: true
  security.syscalls.intercept.mknod: true
  security.syscalls.intercept.setxattr: true
  user.user-data: |
    #cloud-config
    apt:
      sources:
        hashicorp:
          source: "deb https://apt.releases.hashicorp.com jammy main"
          key: |
            -----BEGIN PGP PUBLIC KEY BLOCK-----

            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
            gyzL4vlEB7aSUih7yjgL9s5DKXP2J71dAhIlF8nnM403R2xEeHyivnyeR/9Ifn7M
            PJvUMUuoG+ZANSMkrw//XA31o//TVk9WsLD1Edxt5XZCoR+fS+Vz8ScLwP1d/vQE
            OW/EWzeMRG15C0td1lfHvwPKvf2MN+WLenp9TGZ7A1kEHIpjKvY51AIkX2kW5QLu
            Y3LBb+HGiZ6j7AaU4uYR3kS1+L79v4kyvhhBOgx/8V+b3+2pQIsVOp79ySGvVwpL
            FJ2QUgO15hnlQJrFLRYa0PISKrSWf35KXAy04mjqCYqIGkLsz2qQCY2lGcD5k05z
            bBC4TvxwVxv0ftl2C5Bd0ydl/2YM7GfLrmZmTijK067t4OO+2SROT2oYPDsMtZ6S
            E8vUXvoGpQ8tf5Nkrn2t0zDG3UDtgZY5UVYnZI+xT7WHsCz//8fY3QMvPXAuc33T
            vVdiSfP0aBnZXj6oGs/4Vl1Dmm62XLr13+SMoepMWg2Vt7C8jqKOmhFmSOWyOmRH
            UZJR7nKvTpFnL8atSyFDa4o1bk2U3alOscWS8u8xJ/iMcoONEBhItft6olpMVdzP
            CTrnCAqMjTSPlQU/9EGtp21KQBed2KdAsJBYuPgwaQeyNIvQEOXmINavl58VD72Y
            2T4TFEY8dUiExAYpSodbwBL2fr8DJxOX68WH6e3fF7HwX8LRBjZq0XUwh0KxgHN+
            b9gGXBvgWnJr4NSQGGPiSQVNNHt2ZcBAClYhm+9eC5/VwB+Etg4+1wDmggztiqE=
            =FdUF
            -----END PGP PUBLIC KEY BLOCK-----
    package_update: true
    package_upgrade: true
    packages:
      - docker.io
      - docker-compose
      - git
      - vault
    runcmd:
      - docker volume create bookstack-data
      - docker volume create bookstack-db
      - mkdir /run/bookstack
      - git clone ${GIT_REPO} /root/repo
      - cd /root/repo && git checkout ${GIT_COMMIT}
    write_files:
    - path: /etc/environment
      owner: root:root
      permissions: '0644'
      content: |
        # These environmnt variables were originally put in to place by
        # cloud-init.  They are read in by pam_env whenever a PAM session
        # starts.
        BOOKSTACK_TZ=US/Pacific
        BOOKSTACK_SAML_IDP_NAME="Stanford Login"
        BOOKSTACK_SAML_IDP_ENTITYID=https://login.stanford.edu/metadata.xml
        BOOKSTACK_SECRET_DB_BOOKSTACK_PASSWORD=/run/bookstack/db-bookstack
        BOOKSTACK_SECRET_DB_ROOT_PASSWORD=/run/bookstack/db-root
        BOOKSTACK_SECRET_SAML_CERT=/run/bookstack/sp_cert.pem
        BOOKSTACK_SECRET_SAML_KEY=/run/bookstack/sp_key.pem
        BOOKSTACK_URL=https://${BOOKSTACK_NAME}.stanford.edu
        #BOOKSTACK_AUTH_METHOD=
		#BOOKSTACK_DEBUG=
		#SAML2_DUMP_USER_DETAILS=
        LETS_ENCRYPT_CONTACT=${LETS_ENCRYPT_EMAIL}
        LETS_ENCRYPT_TOS_AGREE=yes
        #LETS_ENCRYPT_STAGING=
        VAULT_ADDR=${VAULT_ADDR}
        VAULT_APPID=${VAULT_APPID}
        #VAULT_SECRET=
        VAULT_MOUNT=${VAULT_MOUNT}
        VAULT_BASE=${VAULT_BASE}
        MAIL_HOST=smtp.stanford.edu
        MAIL_PORT=25
        MAIL_FROM=nobody@stanford.edu
        MAIL_FROM_NAME=Bookstack
    - path: /cloud_init_complete
      owner: root:root
      permissions: '0644'
      content: Hello
EOF


BOOKSTACK_MAC="$(lxc config get ${BOOKSTACK_NAME} volatile.eth0.hwaddr)"
if [ "${PARSABLE:-no}" = "yes" ]; then
	echo "${BOOKSTACK_MAC}"
else
	echo
	echo "MAC address for ${BOOKSTACK_NAME}.stanford.edu is ${BOOKSTACK_MAC}"
	echo 'Now create your NetDB Node, and wait for DHCP to update.'
	echo 'Once DHCP is updated, run:'
	echo " * \`lxc start ${BOOKSTACK_NAME}\` to start the container"
	echo " * \`lxc shell ${BOOKSTACK_NAME}\` to get a shell"
	echo "Once in the shell, wait for the file \`/cloud_init_complete\` to appear."
	echo "You can then access /root/repo and run the next scripts!"
fi

exit 0
