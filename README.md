# Automatic backup of a local directory to S3

You can use the scripts in this directory to automatically back up a local
directory to S3. It's aimed at backing up [FoundryVTT](https://foundryvtt.com/)
worlds, but it will work for any relatively-small set of slowly-changing files.

## Steps

- Follow Amazon's [Batch upload files to the cloud](https://aws.amazon.com/getting-started/hands-on/backup-to-s3-cli/) instructions to:
    - Create an S3 bucket (if you don't already have one)
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

TODO: It wouldn't be hard to make this support multiple directories.
