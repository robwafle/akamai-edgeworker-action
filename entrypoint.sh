#!/bin/bash
set -o pipefail

# Create /root/.edgerc file from env variable
echo -e "${EDGERC}" > ~/.edgerc

#  Set Variables
edgeworkersName=$1
network=$2
groupid=$3
resourceTierId=$4

echo $edgeworkersName
echo $network
echo $groupid

echo ${edgeworkersName}
response=$(akamai edgeworkers list-ids --json edgeworkers.json --section edgeworkers --edgerc ~/.edgerc)
cat edgeworkers.json
edgeworkerList=$( cat edgeworkers.json )
rm edgeworkers.json

edgeworkersID=$(echo ${edgeworkerList} | jq --arg edgeworkersName "${edgeworkersName}" '.data[] | select(.name == $edgeworkersName) | .edgeWorkerId')
#edgeworkersgroupID=$(echo $edgeworkerList | jq --arg edgeworkersName "$edgeworkersName" '.data[] | select(.name == $edgeworkersName) | .groupId')

echo "current edgeworkersID: $edgeworkersID"

if [ -n "${WORKER_DIR}" ]; then
  GITHUB_WORKSPACE="${GITHUB_WORKSPACE}/${WORKER_DIR}"
fi

cd ${GITHUB_WORKSPACE}

tarCommand='tar -czvf ~/deploy.tgz'
# check if needed files exist
mainJSFile='main.js'
bundleFile='bundle.json'
edgekvJSFile='edgekv.js'
edgekv_tokensJSFile='edgekv_tokens.js'
utilitiesDir='utils'
if [ -f $mainJSFile ] ; then 
  tarCommand=${tarCommand}" $mainJSFile"
else
  echo "Error: $mainJSFile is missing" && exit 123
fi
if [ -f $edgekvJSFile ] ; then 
  tarCommand=${tarCommand}" $edgekvJSFile"
else
  echo "Error: $edgekvJSFile is missing" && exit 123
fi
if [ -f $edgekv_tokensJSFile ] ; then 
  tarCommand=${tarCommand}" $edgekv_tokensJSFile"
else
  echo "Error: $edgekv_tokensJSFile is missing" && exit 123
fi 
if [ -f $bundleFile ] ; then 
  tarCommand=${tarCommand}" $bundleFile"
else
  echo "Error: $bundleFile is missing" && exit 123
fi 
# pack optional JS libriries if exist 
if [ -d $utilitiesDir ] ; then 
  tarCommand=${tarCommand}" $utilitiesDir"
fi
# execute tar command
eval $tarCommand
if [ "$?" -ne "0" ]
then
  echo "ERROR: tar command failed" 
  exit 910
fi


if [ -z "$edgeworkersID" ]; then
    edgeworkersgroupID=${groupid}
    # Register ID
    echo "Registering Edgeworker: '${edgeworkersName}' in group '${edgeworkersgroupID}' with resourceTierId '${resourceTierId}' ..."
    edgeworkerRegisterStdOut=$(akamai edgeworkers register \
                      --json --section edgeworkers \
                      --edgerc ~/.edgerc  \
                      --resourceTierId ${resourceTierId} \
                      ${edgeworkersgroupID} \
                      ${edgeworkersName})
    filename=$(echo "${edgeworkerRegisterStdOut##*:}")
    echo ${edgeworkerRegisterStdOut}
    edgeworkerList=$(cat $filename)
    if [[ ! ${edgeworkerList} =~ "Created new EdgeWorker Identifier" ]]; then
      echo "Registration failed!!!! See above."
      exit 920
    fi

    
    echo ${edgeworkerList}
    echo "edgeworker registered!"
    edgeworkersID=$(echo ${edgeworkerList} | jq '.data[] | .edgeWorkerId')
    edgeworkersgroupID=$(echo ${edgeworkerList} | jq '.data[] | .groupId')
fi

echo "Uploading Edgeworker Version ... "
#UPLOAD edgeWorker
uploadreponse=$(akamai edgeworkers upload \
  --edgerc ~/.edgerc \
  --section edgeworkers \
  --bundle ~/deploy.tgz \
  ${edgeworkersID})

echo "Upload Response: ${uploadreponse}"
#TODO: check if upload succeeded
if [[ ! ${uploadreponse} =~ "New version uploaded" ]]; then
  echo "upload failed!!!! See Upload Response above."
  exit 950
fi

edgeworkersVersion=$(echo $(<$GITHUB_WORKSPACE/bundle.json) | jq '.["edgeworker-version"]' | tr -d '"')
echo "Activating Edgeworker Version: ${edgeworkersVersion} ..."
activateStdOut=$(akamai edgeworkers activate \
      --edgerc ~/.edgerc \
      --section edgeworkers \
      ${edgeworkersID} \
      ${network} \
      ${edgeworkersVersion})
echo "activateStdOut:$activateStdOut"
if [[ ! ${activateStdOut} =~ "New Activation record created" ]]; then
  echo "Activation failed!!!! See Upload Response above."
  exit 960
fi
