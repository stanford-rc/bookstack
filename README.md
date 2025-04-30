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
  support for Let's Encrypt.  [It has its own
  repository](https://github.com/stanford-rc/docker-bookstack-certbot).

* **The MariaDB container**: This runs our database!  This is the
  `mariadb:10.11.2` image, pulled from Docker Hub.

* **The Restic container**: This handles our backups.  This image starts with
  the [Restic
  container](https://github.com/restic/restic/pkgs/container/restic), and adds
  some packages & scripts to handle backups of the database.  [It has its own
  repository](https://github.com/stanford-rc/bookstack-restic).

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

* **A Google Cloud project and bucket**: This stores the backups created by
  Restic.

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

* `www/laravel.log`: This has the logs from the PHP Laravel application
  framework.  This is the primary application log.

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

* `GOOGLE_PROJECT_ID`: The ID of the Google Cloud project which stores Restic
  backups.

* `GOOGLE_RESTIC_BUCKET`: The name of the Google Cloud Storage bucket which
  stores Restic backups.

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

* `BOOKSTACK_SECRET_RESTIC_PASSWORD`: This is the path to the file containing
  the password of the Restic repository.  The Restic repository contains all of
  the backup data, and is encrypted using this password.  If you lose or change
  this password, all backups will be lost!

* `BOOKSTACK_SECRET_RESTIC_GOOGLE_CREDENTIALS`: This is the path to the JSON
  file containing credentials for a Google Cloud service account.  This,
  combined with the Project ID and bucket name, will be used to store backups
  via Restic.

* `GOOGLE_PROJECT_ID`: As above, from `GOOGLE_PROJECT_ID`.

* `GOOGLE_RESTIC_BUCKET`: As above, from `GOOGLE_RESTIC_BUCKET`.

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

* `BASE/restic` has a password and a key, used by Restic:

  * `password` contains the password used to encrypt Restic data in the cloud.

  * `gcp` contains the JSON Google Cloud Service Account credential that Restic
    will use.

# Building container images

See the [docker-bookstack-certbot
repo](https://github.com/stanford-rc/docker-bookstack-certbot) for information
on how the container image is built.

For MariaDB, we don't modify the container, we just rely on the MariaDB
containers provided by [MariaDB in Docker
Hub](https://hub.docker.com/_/mariadb/).

See the [booksack-restic repo](https://github.com/stanford-rc/bookstack-restic)
for information on how the Restic container image is built.

# First-Time Installation

This content [has its own page](docs/first-time.md)!

# Accessing the containers

There are three containers:

* The `bookstack-db` container, providing the `db` service, runs MariaDB.

* The `bookstack-app` container, providing the `app` service, runs Bookstack.

* The `bookstack-restic` container, providing the `restic` service, runs
  Restic.

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

# Backup & Restore

This content [has its own page](docs/backups.md).

# Upgrading the containers

Remember, before upgrading anything, be sure to have a backup of everything!

## MariaDB

Upgrading the MariaDB container involves shutting down the entire Docker
Compose stack, sometimes updating the `docker-compose.yaml` file, and bringing
up _just_ the database.  You then run the upgrade command, and bring up the
Bookstack application.

The entire stack must be shut down, because everything in the stack relies on
the database.

To stop the stack, run `docker-compose down`, which will shut down everything,
but leave the volumes intact.

If you plan on doing a major upgrade (such as from 11.4 to 11.7), it's now safe
to update to the newer `docker-compose.yaml` file, and then run `docker-compose
pull db` to download the MariaDB image under the new tag.  If you just want to
upgrade to the latest minor version, skip changing the `docker-compose.yaml`
file, and just run the `docker-compose pull db` command.  This will trigger
Docker Compose to check for a newer container image, under the existing tag.

Next, run `docker-compose up --no-start`.  That creates everything, but does
not start any services.  This will download the new MariaDB container image,
but not start anything.

Next, run `docker-compose start db`.  That will start just the MariaDB
server.  Run `docker logs -f bookstack-db` to see logs from DB server start.

The MariaDB container will automatically detect that you are using a newer
version with an older databasae.  As soon as the server starts, the container's
entrypoint script will run `mariadb-upgrade` for you, restarting the MariaDB
server at the end.  Look for the messages "Finished mariadb-upgrade",
"Temporary server stopped", and finally "mariadbd: ready for connections.".

Now you can run `docker-compose up -d` to bring up the rest of the stack (the
Bookstack server)!

## Bookstack

Upgrading the Bookstack container involves updating the Dockerfile of
[docker-bookstack-certbot](https://github.com/stanford-rc/docker-bookstack-certbot/pkgs/container/docker-bookstack-certbot),
waiting for it to rebuild, restarting the stack, and running post-upgrade
commands.

First, update the `Dockerfile` in the
[docker-bookstack-certbot](https://github.com/stanford-rc/docker-bookstack-certbot)
repository, and wait for the container image to build.

Next, run `docker-compose pull app` to have Docker pull down the updated
container image.  If no new image is found, wait a while and try again.  At
this point, the stack is still running on the older image.

Run `docker-compose up -d`, which should trigger a recreation and restart of the
Bookstack container.  Run `docker logs -f bookstack-app` to see logs from DB
server start.  The updated Bookstack service should see that this is an
upgrade, and run a schema migration (that covers the `php artisan migrate`
command from the [upstream Bookstack upgrade
guide](https://www.bookstackapp.com/docs/admin/updates/)).

The last part of the upgrade is to clear system caches, which can be done with
three commands:

* `docker-compose exec app php /app/www/artisan cache:clear`

* `docker-compose exec app php /app/www/artisan config:clear`

* `docker-compose exec app php /app/www/artisan view:clear`

Finally, depending on the upgrade, you might also need to run additional steps
in the [upstream Bookstack upgrade
guide](https://www.bookstackapp.com/docs/admin/updates/)).

## Restic

Upgrading the Restic container involves upgrading the Dockerfile of
[bookstack-restic](https://github.com/stanford-rc/bookstack-restic), waiting
for it to rebuild, restarting the stack, and running post-upgrade commands.

First, update the `Dockerfile` in the
[bookstack-restic](https://github.com/stanford-rc/bookstack-restic)
repository, and wait for the container image to build.

Next, run `docker-compose pull restic` to have Docker pull down the updated
container image.  If no new image is found, wait a while and try again.  At
this point, the stack is still running on the older image.

Run `docker-compose up -d`, which should trigger a recreation and restart of the
Restic container.  There is no specific command needed to run an upgrade.

The last part of the upgrade is to confirm connectivity is still good, and that
the repository is good.  This can be done with two commands:

* `docker-compose exec restic restic snapshots --latest 1` will connect to the
  repository and return the information from the latest snapshot.

* `docker-compose exec restic restic check` does a consistency check of
  Restic's data, without going as far as downloading all of the pack files.
