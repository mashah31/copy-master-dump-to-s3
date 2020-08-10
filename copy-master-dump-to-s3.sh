#!/bin/bash

# Note: I think pv in the pipe disables buffering on stderr,
# which gives pg_dump more useful output.

set -euo pipefail
SLACK_HOOK=https://hooks.slack.com/services/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
USERNAME=`echo ${BUILD_USER} | awk -F '@' '{print $1}'`

BUCKET_NAME=leantaas-db-dump
PROJECT_NAME=clinics

FILE_NAME=seed.sql
DW_FILE_NAME=seed_dw.sql
ANON_FILE_NAME=anon_seed.sql
ANON_DW_FILE_NAME=anon_seed_dw.sql

DEST_S3=s3://${BUCKET_NAME}/${PROJECT_NAME}/${FILE_NAME}
DW_DEST_S3=s3://${BUCKET_NAME}/${PROJECT_NAME}/${DW_FILE_NAME}
ANON_DEST_S3=s3://${BUCKET_NAME}/${PROJECT_NAME}/${ANON_FILE_NAME}
ANON_DW_DEST_S3=s3://${BUCKET_NAME}/${PROJECT_NAME}/${ANON_DW_FILE_NAME}

CONTAINER_NAME=dump_pg

SOURCE_PASSWORD=$(aws ssm get-parameters --names clinics-test-postgres-key --with-decryption --query "Parameters[0].Value" --output=text)
DW_SOURCE_PASSWORD=$(aws ssm get-parameters --names /clinics/test/dwh_db --with-decryption --query "Parameters[0].Value" --output=text)
ANON_SOURCE_PASSWORD=$(aws ssm get-parameters --names anon-clinics-pqldb-key --with-decryption --query "Parameters[0].Value" --output=text)
ANON_DW_SOURCE_PASSWORD=$(aws ssm get-parameters --names /clinics/anon/dwh_db --with-decryption --query "Parameters[0].Value" --output=text)

#echo "Saving seed to file..."

#SOURCE_PASSWORD=$(aws ssm get-parameters --names clinics-test-postgres-key --with-decryption --query "Parameters[0].Value" --output=text)
#PGPASSWORD="$SOURCE_PASSWORD" pg_dump -F c -x -n "clinics_*" --host=test-clinics-rds --port=5432 --dbname=shared_clinics -U clinics_user -f ${FILE_NAME}

#echo "Uploading to S3..."
#aws s3 cp ${FILE_NAME} ${DEST_S3} --quiet

#LINK=https://${BUCKET_NAME}.s3-us-west-2.amazonaws.com/${PROJECT_NAME}/${FILE_NAME}

#TEXT="CLINICS DB-SEEDER Updated to ${DEST_S3} from MASTER complete"
#curl -s -X POST -H 'Content-type: application/json' --data '{ "attachments": [ { "fallback": "'"$TEXT"'", "text": "'"$TEXT"'", "fields": [ { "title": "USER", "value": "'"$USERNAME"'", "short": true },{ "title": "Download", "value": "'"$LINK"'", "short": true },{ "title": "BUILD URL", "value": "'"${BUILD_URL}"'", "short": true } ], "color": "info" } ] }' $SLACK_HOOK


dump_fn () {

# 1 = dump name
# 2 = dump password
# 3 = source db host
# 4 = source db dbname
# 5 = source db username
# 6 = dump filename
# 7 = s3 URL

echo "Saving $1 seed to file..."
echo "Cleaning up docker containers"
docker stop ${CONTAINER_NAME} || true
docker rm ${CONTAINER_NAME} || true
sleep 5

echo "Starting $1 container"
docker run -d --name ${CONTAINER_NAME} -e PGPASSWORD="$2" -e POSTGRES_HOST_AUTH_METHOD=trust --rm -t postgres:11 
echo "Running pg_dump"
docker exec ${CONTAINER_NAME} pg_dump -v -F c -Z 9 -x -n "clinics_*" --host="$3" --port=5432 --dbname="$4" -U "$5" > "$6"
echo "Killing the docker container"
docker kill ${CONTAINER_NAME}

echo "Uploading dw to S3..."
aws s3 cp "$6" "$7" --quiet

LINK=https://${BUCKET_NAME}.s3-us-west-2.amazonaws.com/${PROJECT_NAME}/"$6"

TEXT="CLINICS DW DB-SEEDER Updated to $7 from MASTER complete"
curl -s -X POST -H 'Content-type: application/json' --data '{ "attachments": [ { "fallback": "'"$TEXT"'", "text": "'"$TEXT"'", "fields": [ { "title": "USER", "value": "'"$USERNAME"'", "short": true },{ "title": "Download", "value": "'"$LINK"'", "short": true },{ "title": "BUILD URL", "value": "'"${BUILD_URL}"'", "short": true } ], "color": "info" } ] }' $SLACK_HOOK


}

dump_fn "db" "$SOURCE_PASSWORD" "test-clinics-rds" "shared_clinics" "clinics_user" "$FILE_NAME" "$DEST_S3"
dump_fn "dw" "$DW_SOURCE_PASSWORD" "test-clinics-dwh-rds" "clinics_reporting" "clinics_u" "$DW_FILE_NAME" "$DW_DEST_S3"
dump_fn "anon" "$ANON_SOURCE_PASSWORD" "anon-clinics-rds" "shared_clinics" "clinics_user" "$ANON_FILE_NAME" "$ANON_DEST_S3"
dump_fn "anon dw" "$ANON_DW_SOURCE_PASSWORD" "anon-clinics-dwh-rds" "clinics_reporting" "clinics_u" "$ANON_DW_FILE_NAME" "$ANON_DW_DEST_S3"

rm -f ${FILE_NAME} ${DW_FILE_NAME} ${ANON_FILE_NAME} ${ANON_DW_FILE_NAME}
