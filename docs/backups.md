Backups are managed by Restic by the
[bookstack-restic](https://github.com/stanford-rc/bookstack-restic) container.
Backups happen every 15 minutes.  A backup happens by dumping the `mysql` and
`bookstack` databases, and backing up those dumps and all other static content.

# Backups Status

If you want to make sure backups are working, pull the list of Restic
snapshots with `docker-compose exec restic restic snapshots`.  That lists all
of the backups.

# Retention and Cleanup

Older backups are removed every time a new backup is taken,
based on a schedule that you set: Some number of hourly, daily, weekly,
monthly, and yearly backups can be retained.

The current configuration keeps 48 hourly backups, 7 daily backups, 4 weekly
backups, and 18 monthly backups.

"Removing" a backup, however, does not actually remove the "pack files" (or
"packs") that are stored in the cloud.  Since multiple snapshots can be stored
in a pack, repacking involves reading data from the cloud, which can be pricey.
So, data are only repacked when a snapshot has more than some set amount of
data.  Once that threshold is passed, a pack file will be downloaded and
re-packed, removing unused data.

Since Google Cloud Storage Autoclass is used in the current setup, the current
configuration allows pack files to have up to 80% unused data before they are
repacked.

# Restoring Bookstack from backup

If you need to roll back an entire Bookstack installation to that saved in a
backup, or you need to restore Bookstack after some sort of disaster, here is
how to do it.

Before you start the restore proper, there is some prep work you need to do
first:

* If you don't have a working machine, create it (likely using the
  `create-lxc.sh` script).

* If you don't have the secrets from Vault, fetch them (likely using the
  `fetch-vault.sh` script).

* If you don't have the Docker volumes (`bookstack-data` and `bookstack-db`),
  create them.

  If you already have the volumes—say, because you're doing a rollback—you will
  need to delete and re-create them.  For safety, you may wish to make an
  archive of the underlying volume filesystems, before you do this.

* If the stack is running, take it down (`docker-compose down`).

Now you can begin the restore.

1. Use `docker-compose up --no-start` to create the stack, but to not start any
   services.

2. Start just the database, using `docker-compose start db`.  Check the logs
   (`docker-compose logs db`), looking for "Initializing database files" (a new
   server is being set up) and "mariadbd: ready for connections." (setup is
   complete).

3. Restore all of the data files to the Bookstack data volume.  Two of those
   files are the SQL dumps of the `mysql` and `bookstack` databases.  Since the
   Restic container is not running (we don't want it to back up right now), we
   will bring up a one-time instance of Restic.  The command for running this
   container is `docker-compose run restic restic …`: The first `restic` is the
   service name; the second `restic` is the command.

   The bookstack data volume is mounted at path `/bookstack` in the Restic
   container.  Restic wants a restore target, to which Restic will add the
   `/bookstack` path.  So, the full command to restore the latest snapshot is
   `docker-compose run restic restic restore --target / latest`.

   If you want to restore from a different snapshot, run `docker-compose run
   restic restic snapshots` to see a list of available snapshots.

4. Restore the databases, both the `msql` database and the `bookstack`
   database.  The backups can be found in path `/bookstack/backups`.  The
   Restic container provides access to the `mysql` command; since the Restic
   container has access to both the database server and the Bookstack data
   files, we will use the one-time Restic container for these restores.

   Two restores are needed, one for each database.

   `docker-compose run restic mysql --execute 'source
   /bookstack/backups/mysql.sql'; FLUSH PRIVILEGES` will restore the MySQL
   database and reload privileges (so MariaDB picks up the correct password for
   the Bookstack user).

   `docker-compose run restic mysql --execute 'source
   /bookstack/backups/bookstack.sql'` will restore the Bookstack database.  As
   a sanity check, after doing this restore you can use `docker-compose run
   restic mysql --execute 'SHOW TABLES' bookstack` to check if tables were
   created.

5. Start the Bookstack service, using `docker-compose start app`.  Check the
   logs (`docker-compose logs --follow app`) to confirm startup was successful:
   The startup scripts should find an existing database, report "Nothing to
   migrate", and Let's Encrypt should report that it is "Keeping the existing
   certificate".

6. Open the Bookstack site and log in.  You should find your content restored.

7. Finally, bring up the rest of the stack, using `docker-compose up -d`.  This
   should only start the Restic service.

Congratulations, you've done a restore of Bookstack!
