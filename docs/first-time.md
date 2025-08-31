This page has the information you need to set up a Bookstack server!

## Creating a Google Cloud Storage bucket

Backups will be stored in a Google Cloud Storage bucket

* **Create a Project**: If you don't have one already, create a Google Cloud
  Storage project.  Make a note of the Project ID (not the number, or
  description, the ID).

* **Create a Bucket**: Create a Google Cloud Storage bucket.  This can be a
  single-region bucket.  Use Autoclass, and allow storage in Coldline and
  Archive classes.  Ensure public access is disabled.  Make note of the bucket
  name.

* **Create a Service Account**: Create a Service Account.  The Service Account
  will need "Storage Object Admin" access, with the following condition
  (written in Condition Editor's 'CEL' format):

```
(
  resource.service == "storage.googleapis.com" &&
  resource.type == "storage.googleapis.com/Bucket" &&
  resource.name == "projects/_/buckets/BUCKET_NAME"
) || (
  resource.service == "storage.googleapis.com" &&
  resource.type == "storage.googleapis.com/Object" &&
  resource.name.startsWith("projects/_/buckets/BUCKET_NAME/objects/")
)
```

  Replace `BUCKET_NAME` with your bucket's name (you'll have to replace it in
  two loations).  This will give the Service Account permissions to list
  objects in the bucket, and permission to add/get/change/delete inidividual
  objects.

  Download the JSON credentials for the Service Account.

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

To check if cloud-init has finished, run `journalctl -f` and look for the
message "Reached target Cloud-init target.".  Of, run `systemctl status
cloud-init.target` and check if the unit is "active" or still "activating".

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

Finally, make a note of your certificate's end date.  The date is provided in
both human-readable form (for entry into a calendar reminder or other
notification program), and in the form that you'll need to insert in to SAML
metadata.

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

* Set `LETS_ENCRYPT_STAGING` if you are using the Let's Encrypt Staging
  environment.

A fresh LXC does not set these environment variables.  Once first-time setup is
complete, you should put them in `/etc/environment` as appropriate!

To create the services, run `cd ~/repo && docker compose up`.  That will start
up the database (including creating a new DB, if needed), and then start up
Bookstack.  The first run of Bookstack will include requesting a certificate
from Let's Encrypt.

Bookstack is now up, but without an administrator.  The default account has
email address `admin@admin.com` and password `password`, but does not work when
SAML authentication is enabled.  That's a good thing, because the creation of
the Let's Encrypt certificate has told the world that the site exists, so we
don't want the default credentials to be accessible.

## Configure Backups

Once the Bookstack site is up, even though it has not been configured, you can
proceed to set up backups.

Enter the Restic container with `docker exec -it bookstack-restic`.  Inside the
container, run `restic init`.  All the configuration and credentials are passed
via environment variables, so Restic will use those to create the repository.

At the end, you should have a message saying that the repository has been
created.  If you check the Google Cloud Storage bucket, you should see at least
a `config` file and a `keys` directory.

Every 15 minutes, Restic will take a backup.  So backups are now complete!

## Configuring SAML

On a first run of Bookstack, the SAML SP is configured, but the IdP is not, and
there is no administrator.  The process of configuring SAML has three steps:

1. Update the IdP with the SP's metadata.

2. Create an administrator.

3. Log in.

Each step is covered below.

### Update the IdP

Navigate to `https://YOUR_BOOKSTACK_SITE/saml2/metadata`.  This will give you
the SAML2 metadata XML.

Go to the [SPDB](https://spdb.stanford.edu/), and paste in your SP metadata XML.
You will need to set several parameters:

* Set the *Contact* field to your group's contact email.

* Set the *Login URL* to `https://YOUR_BOOKSTACK_SITE/saml2/login`.

* In the Metadata, edit the top-level `md:EntityDescriptor` element: Change
  `validUntil` to match the end date of your SAML SP certificate.  When you
  created your SAML certificate, you were given the exact string to enter.

Once your SPDB record is accepted, continue setup while waiting for Stanford
Login to pick up the new SP metadata (it takes about 15 minutes).

### Create a local account

Bookstack provides a command-line way to create an administrator account, for
times like this when there is no administrator account.  The command to run is:

```
docker-compose exec app php /app/www/artisan bookstack:create-admin --email="sunetid@stanford.edu" --name="Somebody" --external-auth-id="sunetid"
```

(Replace the two instances of `sunetid` with your SUNetID.)

This command runs the manual account-creation process, using your email
address, name, and SUNetID.  The `external-auth-id` in particular is important:
That must match your SUNetID, even if you have a different email address.

### Log in

Before you can log in, you need to wait for the IdP to update with the metadata
you uploaded to the SPDB.  The way you can be certain the change has taken
effect is to download the IdP's [list of all SP metadata](https://samlmetadata.stanford.edu/sp-metadata.xml), and search for your SP's `entityId`.

Once you see your SP in the list, try to log in!

If everything works, you should be sent through Stanford Login, and then back
to Bookstack.  You will be logged in, and if you have a
[Gravatar](https://gravatar.com/) attached to your email address, it will be
showing.

You can now proceed to set up Bookstack!

## Finishing Bookstack configuration

TODO!
