# Automatic backup of a local directory to S3

You can use the scripts in this directory to automatically back up a local
directory to S3. It's aimed at backing up [FoundryVTT](https://foundryvtt.com/)
worlds, but it will work for any relatively-small set of slowly-changing files.

## Steps

- Follow Amazon's [Batch upload files to the cloud](https://aws.amazon.com/getting-started/hands-on/backup-to-s3-cli/) instructions to:
    - Create an S3 bucket (if you don't already have one)
        - **NOTE TO FOUNDRY VTT USERS**: I strongly recommend that you do *not*
          use your Foundry data S3 bucket for backups. Foundry requires that it
          be publicly readable, which means anyone would be able to see your
          backup data. Do you really want your dumb chat log jokes (and maybe
          your license key, depending on what you back up) just hanging out
          there?
    - Create an IAM user that can read/write the bucket (or grant an existing
      user read/write permissions)
    - Install and configure the `aws` tool with that user's credentials

- Read the header comment of [`backup-to-s3.sh`](backup-to-s3.sh) and ensure the
  prerequisites are met.

- Clone this repo (`s3-backup-cron`) to your local system. For example:

    ```shell
    mkdir /tmp/s3backup
    cd /tmp/s3backup
    git clone git@bitbucket.org:dbort/s3-backup-cron.git
    cd s3-backup-cron
    ```

- Run `./install.sh` and answer the questions.

- Run `crontab -e` and paste the recommended line into the cron file.
  See https://crontab.guru/ for help with changing when and how often it
  runs.

That should do it! You can watch the log file (defaults to a file under
`~/var/log`) to see if it succeeded or failed.

To try it without waiting all night, copy the command from the crontab line
(skipping past the asterisks), paste into a bash shell, then look at the log
file.

## Possible future improvements

- Support multiple directories.
- Encrypt backups or at least give them zip passwords.
- Add options for picking archive formats other than zip.
