#!/bin/bash

#------------------------------------------------------------------------------------
#title           :deploy.sh
#description     :This script will deploy app using ansible.
#author          :Arlindo Santos
#date            :2016-Dec-06
#
#------------------------------------------------------------------------------------

function getGitProjectVersion (){
        local revisioncount
	local projectversion

	CI_PUSH_REPO=$(echo ${CI_BUILD_REPO} | perl -pe 's#.*@(.+?(\:\d+)?)/#git@\1:#')
	git remote set-url --push origin "${CI_PUSH_REPO}"
	git tag 1.0.0 &> /dev/null
	git push origin 1.0.0
	revisioncount=$(git log --oneline | wc -l | tr -d ' ')
	projectversion=$(git describe --tags | awk '{split($0,a,"-"); print a[1]}')
	echo "${projectversion}-Build-${CI_PIPELINE_ID}"
}
function getGitProjectCommitSHA (){
	echo "Build-${CI_BUILD_REF}"
}


function zipupAppPackage() {
	zip -q -r $PROJECT_NAME-$VERSION.zip $PROJECT_NAME
}

function sendSlackNotifications() {
	curl -X POST --data-urlencode 'payload={"channel": "'"$CHANNEL"'", "username": "gitlab", "text": "'"$SLACK_MSG"'"}' "$CI_SLACK_WEBHOOK_URL"

}

function sendToS3() {
	aws s3 cp --quiet ${PROJECT_NAME}-${VERSION}.zip s3://${S3BUCKETNAME}/${PROJECT_NAME}/
}

function doesPackageNotExistInS3() {
	aws s3 ls s3://${S3BUCKETNAME}/${PROJECT_NAME}/ | grep ${PROJECT_NAME}-${VERSION}.zip > /dev/null
	echo $?
}

function log() {
        echo "$(date):$@"
}

function logStep() {
	echo "$(date):====================================================================================="
        echo "$(date):$@"
	echo "$(date):====================================================================================="
	echo ""
}

function cloneAnsibleProject() {
	rm -Rf ansible-appx
	git clone https://gitlab-ci-token:${CI_BUILD_TOKEN}@git.x.com/appx/ansible-appx.git
}

function deployWithAnsible() {
	ansible-playbook -i inventory/${ENV}/ -e "appx_buildnumber=$VERSION appx_projectname=$PROJECT_NAME ansible_ssh_private_key_file=~/.ssh/ansible_prod.pem" playbooks/deployappx.yml -t "appx:deploy" --vault-password-file ~/.ansible_appx_vault_pass.txt
}

function error() {
    	local job="$0"              # job name
    	local lastline="$1"         # line of error occurrence
    	local lasterr="$2"          # error code
    	log "ERROR in ${job} : line ${lastline} with exit code ${lasterr}"
        SLACK_MSG="FAILURE - appx app version ${VERSION} failed Deployment to ${ENVMSG}"
        sendSlackNotifications
    	exit 1
}

function cleanup() {
	rm -Rf $PROJECT_NAME-$VERSION.zip

}

#----------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------

trap cleanup SIGHUP SIGINT SIGTERM EXIT
trap 'error ${LINENO} ${?}' ERR

PROJECT_NAME=$(basename $CI_PROJECT_DIR)
CHANNEL=${SLACKCHANNEL}
S3BUCKETNAME="code-repo.arlindo.ca"

ENV="${1}"
ENVMSG="${2}"

#-----------------------------------------------
# Step 1 - tag and get git version for app
#-----------------------------------------------
logStep " STEP 1 - Tag and get git version for app"

#VERSION=$(getGitProjectVersion)
VERSION=$(getGitProjectCommitSHA)
echo "Version Info: ${VERSION}"

cd ..

if (( $(doesPackageNotExistInS3) )); then

	#-----------------------------------------------
	# Step 2 - zip up the app with version info #-----------------------------------------------
	logStep " STEP 2 - Zip up the app with version info"
	zipupAppPackage

	#-----------------------------------------------
	# Step 3 - send zip to s3 code repo
	#-----------------------------------------------
	logStep " STEP 3 - Send zip package to s3 code repo"
	sendToS3
else
	logStep " STEP 2 and 3 Skipping - package already exists in s3..."
fi

#-----------------------------------------------
# Step 4
#-----------------------------------------------
logStep " STEP 4 - Deploy app with ansible"
cloneAnsibleProject
cd ansible-appx
deployWithAnsible

#-----------------------------------------------
# Step 5
#-----------------------------------------------
logStep " STEP 5 - Send Notifications to Slack"
SLACK_MSG="SUCCESS - appx app version ${VERSION} successfully Deployed to ${ENVMSG}"
sendSlackNotifications

#-----------------------------------------------
# Step 6 - CleanUp
#-----------------------------------------------
cd ..
cleanup
logStep " DONE!"


exit
