[Bookstack](http://bookstackapp.com) is a Wiki app.  But it has several
features that make it a good place to store internal documentation:

* It supports multiple Wikis (which it calls "books").  It allows organization
  of Wikis (by placing "books" in "shelves").  This means it's possible to put
  internal docs for multiple services in one place, while allowing each service
  to remain self-contained.

* Searching and linking are built in.  Content is indexed automatically, so you
  can use one search page to search (if you want) across everything you can
  access.  It's also possible to make intra- and inter-book links.

* Built-in diagrams.  Bookstack uses [diagrams.net](diagrams.net) for diagrams,
  storing the diagram data as page data.

* It can be connected to SAML, so we don't need to set up separate
  authentication in order to run it.

* Bookstack has an API, and can also call Webhooks when things happen.

Bookstack uses a MariaDB databasae to store things like articles, and it uses a
path on the filesystem to store things like attachments.

Bookstack, MariaDB, etc. all have good container implementations, so for
portability, we use those!

# The parts of Bookstack

* **The Containerhost**: Our containerhost runs LXC, and inside that VM we
  run Docker.  Within that system, system-wide environment variables are used
  to pass important paths to Docker, which passes them into the containers.

  In order to run Docker inside of an LXC container-based VM, three security
  settings must be enabled:

  * `security.nesting`: This allows creating containers inside of containers.

  * `security.syscalls.intercept.mknod`: This is [needed by Systemd](https://systemd.io/CONTAINER_INTERFACE/).

  * `security.syscalls.intercept.setxattr`: Extended attributes are used by
    Docker's `overlay2` storage driver, which uses overlay file systems to
    mount a container image.

* **The Bookstack-with-Let'sEncrypt container**: This image starts with the
  [LinuxServer.io](https://linuxserver.io) [Bookstack
  container](https://docs.linuxserver.io/images/docker-bookstack), and adds
  support for Let's Encrypt.

* **The MariaDB container**: This runs our database!  This is the
  `mariadb:10.11.2` image, pulled from Docker Hub.

* **Docker Compose**: Docker Compose is used to bring up the Bookstack
  environment, and to connect containers to their ports and filesystems.

  Why use Docker Compose instead of Kubernetes?  Docker compose is a lot
  simpler to configure, 

* **TCP Ports 80 & 443**: The Bookstack container uses both ports 80 and 443.
  Port 80 is specifically required by the ACME [HTTP-01
  challenge](https://letsencrypt.org/docs/challenge-types/#http-01-challenge),
  used by Let's Encrypt.

* **A backend network**: Docker Compose creates a backend network, used solely
  to connect the Bookstack container to port 3306 on the MariaDB container.
  The MariaDB container cannot be access from the outside world.

* **A DB volume**: Named `bookstack-db`, this stores the database's data files.
  This must only be accessed by MariaDB.  If you want to take backups, use
  appropriate backup tools!

* **A data volume**: Named `bookstack-data`, this stores everything else
  related to Bookstack, except for code.  The specific paths to things are
  explained in a following section.

* **Vault**: [Stanford Vault](https://vault.stanford.edu) is used to store all
  of the secrets needed by the container.  That being said, most secrets are
  only pulled from Vault at install-time.  A Vault AppRole is used to provide
  access to the secrets.

## Data Volume Paths

The following paths exist in the VM's data volume:

* `BOOKSTACK_APP_KEY.txt`: The API key to get admin access to Bookstack,
  through it's API.

* `cert`: This has a self-signed TLS cert and key.  They are not used, and
  should be left alone.

* `log/letsencrypt`: Certbot logs are placed here.

* `log/nginx`: Nginx web server access and error logs are placed here.

* `log/php/error.log`: PHP-level logs, including logs from FPM (the PHP FastCGI
  implementation), are here.

* `nginx`: All of Nginx's configuration is here.  It should be left alone.

* `php`: PHP's configuration is here.  It should be left alone.

* `www`: TODO



## Variables

The following variables are needed to create the Bookstack VM:

* `BOOKSTACK_NAME`: This is the hostname of the LXC VM.  For example,
  `rc-bookstack-srcf`.  This will form the hostname part of the app's URL,
  under the stanford.edu domain.

* `LETS_ENCRYPT_EMAIL`: This is the email that Let's Encrypt will use for
  notifications.  For example, `srcc-support@stanford.edu`.

* `VAULT_APPID`: The Vault AppRole ID.

* `VAULT_ADDR`: The address (URL) of the Vault server.

* `VAULT_MOUNT`: The mountpoint of the Key-Value Secrets Engine.

* `VAULT_BASE`: The base path for our secrets.

The following environment variables are used by the Bookstack containers:

* `BOOKSTACK_URL`: The URL to the Bookstack site.  It's formed by taking
  `BOOKSTACK_NAME`, appending domain `stanford.edu`, as
  `https://${BOOKSTACK_NAME}.stanford.edu`.

* `LETS_ENCRYPT_CONTACT`: As above, from `LETS_ENCRYPT_EMAIL`.

* `LETS_ENCRYPT_TOS_AGREE`: Hard-coded to `yes`.  When using the LXC deployment
  script—described later on this page—you are prompted to read & agree to the
  [Let's Encrypt Terms of Service](https://letsencrypt.org/repository/).

* `LETS_ENCRYPT_STAGING`: This is optional.  If it's set, Certbot will use the
  Let's Encrypt staging environment.

* `BOOKSTACK_TZ`: The Olsen time zone ID for the Bookstack application.  It
  influences how times are displayed.  Hard-coded to `US/Pacific`.

* `BOOKSTACK_AUTH_METHOD`: The authentication method to use.  This is either
  `standard` (username/password) or `saml2`.

* `BOOKSTACK_SAML_IDP_NAME`: The name of the SAML-based login method that
  Bookstack will present to users.  Hard-coded to "Stanford Login".

* `BOOKSTACK_SAML_IDP_ENTITYID`: The URL to the SAML IdP's metadata.
  Hard-coded to the Stanford Login IdP metadata.

* `BOOKSTACK_SECRET_SAML_CERT`: This is the path to the file containing the
  Bookstack SAML SP certificate.

* `BOOKSTACK_SECRET_SAML_KEY`: This is the path to the file containing the
  Bookstack SAML SP private key.

* `BOOKSTACK_SAML_DUMP_USER_DETAILS`: This variable is normally not set.  If it
  is set, and `BOOKSTACK_AUTH_METHOD` is set to `saml2`: then the normal
  Bookstack app will be disabled.  Instead, when you log in, you will be
  presented with a JSON-format dump of all the attributes received from the
  SAML IdP, along with the values of what Bookstack will be using for its
  attributes (`exernal_id`, `name`, `email`, etc.).

* `BOOKSTACK_DEBUG`: This variable is normally not set.  If it is set, logs of
  additional detail—**including secrets**—are output to logs.

* `BOOKSTACK_SECRET_DB_BOOKSTACK_PASSWORD`: In MariaDB, a user `bookstack` is
  given full access to database `bookstack`.  This is the path to the file
  containing the password.

* `BOOKSTACK_SECRET_DB_ROOT_PASSWORD`: This is the path to the file containing
  the MariaDB root password.

* `MAIL_HOST`: The SMTP server that receives email.  It must support TLS.

* `MAIL_PORT`: The port to use for SMTP.

* `MAIL_FROM`: The email address to use for sending mail.

* `MAIL_FROM_NAME`: The name to use with the sending email address.

## Vault Paths

The following paths are pulled from Vault, off of some base path (represented
here as `BASE`:

* `BASE/saml` has two keys, which must be updated in sync:

  * `cert` contains the SAML SP certificate

  * `key` contains the SAML SP key

* `BASE/db` has two passwords, used by the Database server:

  * `bookstack` contains the password for the `bookstack` database user

  * `root` contains the MariaDB root password

# Building container images

See the [docker-bookstack-certbot
repo](https://github.com/stanford-rc/docker-bookstack-certbot) for information
on how the container image is built.

For MariaDB, we don't modify the container, we just rely on the MariaDB
containers provided by [MariaDB in Docker
Hub](https://hub.docker.com/_/mariadb/).

# First-Time Installation

## Creating the VM on containerhost

Before you create the VM on containerhost, make sure your chosen hostname is
free in NetDB.  Create the NetDB Node, without any NetDB Interfaces (you'll add
one later).  Doing this will 'reserve' the name.

To create the VM on the containerhost, use the script `create-lxc.sh`.  You'll
need to run this script on the containerhost itself, but you don't need to run
it as root, you just need to run it as a user that can create VMs.

The script collects the necessary variables, confirms you agree to the [Let's
Encrypt Terms of Service](https://letsencrypt.org/repository/), creates the VM,
and gives you the information needed to update NetDB and start the VM.

The variables collected by the VM are defined in the previous section.

An Ubuntu 22.04 LTS container-based VM will be created, with two CPU cores, 8
GiB of memory, and the security settings defined above.

User data contains [cloud-config
YAML](https://cloudinit.readthedocs.io/en/latest/reference/examples.html),
which does the following:

1. Load the Hashicorp Debian repo GPG key.

2. Update package repos, and then `apt upgrade` to update any out-of-date
 packages (within the given release).

3. Install the `docker.io`, `docker-compose`, `git`, and `vault` packages.  The
 `vault` package is the only one coming from the Hashicorp repo.
 Installing the packages automatically starts Docker.

4. Create volumes `bookstack-data` and `bookstack-db`.

5. Create directory `/run/bookstack`, which will hold all of the Docker
 Compose secrets to be passed to the containers.

6. Check out this Git repo; to a branch, tag, or commit you specify.

7. Populate `/etc/environment` with all of the environment variables defined
 above.

8. Create file `/cloud_init_complete`, as a marker file.

The VM creation script does not currently download or deploy anything with
Docker Compose.  That's up to you!

At the end, you are given the MAC address of the VM.  You should now go in to
your NetDB Node, create an interface, load the MAC & enable DHCP, and allocate
IPv4 & IPv6 IPs.

The VM-creation script does not actually start the VM!  You should wait for DNS
and DHCP to propagate before you start the VM.  Doing so will ensure the VM
gets its IPs immediately on start.

To start the VM, you can use the `lxc start` command.  Use `lxc shell` to
access the shell, which will be live almost immediately after starting.  That
means you will be able to shell in before cloud-init has completed, so be on
the lookout for the `/cloud_init_complete` file!

## Creating a SAML key & certificate

The script `create-saml-cert.sh` will create the SAML SP certificate and key
needed to SAML authentication.  They need to be provided to Bookstack, which
then generates the SAML SP Metadata.

The script can be run on any system that can run BASH scripts and which has
OpenSSL (and the `openssl` command) installed.  The script will create a script
valid for two years.

Once you have a SAML key and certificate, load them into Vault, so they can be
picked up in the VM.

Finally, make a note of your certificate's end date.  You'll need it later in
the first-time setup process.

## Fetching secrets from Vault into the VM

The script `fetch-vault.sh` fetches all of our credentials from Vault, and
places it into the appropriate locations for Docker to pass on to containers.

The script picks up all of its configuration from the environment, specifically
from the variables stored in `/etc/environment`.  The only thing missing is the
Vault AppRole Secret ID.  The script will prompt for the secret at runtime, or
you may put it into the `VAULT_SECRET` environment variable.

## Bringing up the Docker Compose stack

With the VM up and the secrets retrieved, you should now set the final
environment variables:

* Set `BOOKSTACK_AUTH_METHOD` to `standard`.

* Set `LETS_ENCRYPT_STAGING` if you are using the Let's Encrypt Staging
  environment.

A fresh LXC does not set these environment variables.  Once first-time setup is
complete, you should put them in `/etc/environment` as appropriate!

To create the services, run `cd ~/repo && docker compose up`.  That will start
up the database (including creating a new DB, if needed), and then start up
Bookstack.  The first run of Bookstack will include requesting a certificate
from Let's Encrypt.

On the first run, with standard login, the default account has email address
`admin@admin.com` and password password`.

## Configuring SAML

On a first run of Bookstack, SAML is not configured.  The process of
configuring SAML has three steps:

1. Start Bookstack with standard (email & password) authentication, log in, and
   change your admin password.

2. Switch to SAML, log in, and then switch back to standard auth.

3. Log in as the local admin, give your SAML account admin rights, and switch
   back to SAML.

Each step is covered below.

### First Login

On your first login, make sure you can log in, and that the (empty) site is
there.  Logins trigger an audit log entry, so just logging in is enough to test
that the database is up, with writes enabled.

Go to the *Edit Profile* menu, and change your password.

### First SAML Switch & Metadata load

Log out of Bookstack, then shut down the stack (with `docker-compose down`.
Change the `BOOKSTACK_AUTH_METHOD` environment variable to `saml2`, and bring
the stack back up (`docker-compose up`).

Once the application is running, navigate to
`https://YOUR_BOOKSTACK_SITE/saml2/metadata`.  This will give you the SAML 2
metadata XML.

Go to the [SPDB](https://spdb.stanford.edu/), and paste in your SP metadata XML.
You will need to set several parameters:

* Set the *Contact* field to your group's contact email.

* Set the *Login URL* to `https://YOUR_BOOKSTACK_SITE/saml2/login`.

* In the Metadata, edit the top-level `md:EntityDescriptor` element: Change
  `validUntil` to match the end date of your SAML SP certificate.

Once your SPDB record is accepted, wait for Stanford Login to pick up the new
SP metadata (it takes about 15 minutes).  Then, try to log in!

If everything works, you should be sent through Stanford Login, and then back
to Bookstack.  You will be logged in, and if you have a
[Gravatar](https://gravatar.com/) attached to your email address, it will be
showing.

### Switch back to Standard, grant admin-ship, and switch back to SAML

Log out of Bookstack, then shut down the stack agian (`docker-compose down`).
Change the `BOOKSTACK_AUTH_METHOD` to `standard`, and bring up the stack
(`docker-compose up`).

Log in to Bookstack using the static credentials (`admin@admin.com`, and the
password you set).  Go to *Settings*, then *Users*, and locate the user entry
for your SAML account.  Click on that, and add them to the "Admin" role.  Save
changed!

Log out of Bookstack, and once again do the dance of shutting down the stack
(`docker-compose down`), updating `BOOKSTACK_AUTH_METHOD` to `saml2`, and
bringing the stack back up (`docker-compose up`).

You should now edit `/etc/environment`, ensuring `BOOKSTACK_AUTH_METHOD` is
defined and set to `saml2`.

Log back in to Bookstack.  You should go through Stanford Login once again, but
this time you should have Bookstack admin access.  You can now proceed to set
up Bookstack!

## Finishing Bookstack configuration

TODO!

# Accessing the containers

There are two containers:

* The `bookstack-db` container, providing the `db` service, runs MariaDB.

* The `bookstack-app` container, providing the `app` service, runs Bookstack.

When they're running, you can access the container environments with `docker
exec -it CONTAINER_NAME bash`.  You can also read logs from the container using
`docker logs CONTAINER_NAME`.

There are two data volumes:

* The `bookstack-data` volume has the files from the `bookstack-app` container.

* The `bookstack-db` volume has the MariaDB database files from the
  `bookstack-db` container.

The command `docker volume inspect VOLUME_NAME` command gives you, among other
things, the path to volume files.  *Don't mess with these files while its
container is running!*
