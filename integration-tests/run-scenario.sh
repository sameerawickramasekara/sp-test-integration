#! /bin/bash

# Copyright (c) 2018, WSO2 Inc. (http://wso2.com) All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#set -e
set -o xtrace

#retry connecting to wum
connect_to_wum_server(){
    x=1;
    while [[ $x -eq 2 ]];
    do
        # wait for 15 seconds before check again
        sleep 15
        wum add -y ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION}
        if [ "$?" -eq "0" ]; then
            echo "Downloading WUM Pack.."
        else
             x=$((x+1))
        fi
    done
}

set_product_pack(){

#Defining Test Modes
TEST_MODE_1="WUM"

#WUM product pack directory to check if its already exist
PRODUCT_FILE_DIR="/home/ubuntu/.wum3/products/${PRODUCT_CODE}"

if [ ${TEST_MODE} == "$TEST_MODE_1" ]; then
   wget -nv -nc https://product-dist.wso2.com/downloads/wum/3.0.0/wum-3.0.0-linux-x64.tar.gz
   echo 1qaz2wsx@E | sudo -S tar -C /usr/local -xzf wum-3.0.0-linux-x64.tar.gz

   if [ "$?" -ne "0" ]; then
      echo "Error while untar the product pack or low disk space. Hence skipping the execution!"
      exit 1
   else
      export PATH=$PATH:/usr/local/wum/bin
   fi

   wum init -u ${USER_NAME} -p ${PASSWORD}

   #pointing to WUM UAT environment
   wum config repositories.wso2.url ${WUM_UAT_URL}
   wum config repositories.wso2.appkey ${WUM_UAT_APPKEY}

   #needs to initialize wum again to update the username in the config.yaml file

   wum init -u ${USER_NAME} -p ${PASSWORD}

   if [ -d "$PRODUCT_FILE_DIR" ]; then
      echo 'Updating the WUM Product....'
      set +e
      wum update ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION}
      wum describe ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION} ${WUM_CHANNEL}
      echo 'Product Path'
      wum_path=$(wum describe ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION} ${WUM_CHANNEL} | grep Product | grep Path |  grep "[a-zA-Z0-9+.,/,-]*$" -o)
      echo $wum_path
   else
      set +e
      echo 'Adding WUM Product...'
      wum add -y ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION}
        if [ "$?" -eq "0" ]; then
            echo 'Updating the WUM Product...'
            wum update ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION}
            wum describe ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION} ${WUM_CHANNEL}
            echo 'Product Path...'
            wum_path=$(wum describe ${PRODUCT_CODE}-${WUM_PRODUCT_VERSION} ${WUM_CHANNEL} | grep Product | grep Path |  grep "[a-zA-Z0-9+.,/,-]*$" -o)
            echo $wum_path
        else
            connect_to_wum_server
            echo 'Failed to connecting to WUM server, Hence skipping the execution!'
        fi
   fi
else
   echo "Error while setting up WUM"
fi

}

# set_product_pack

DIR=$2
echo $DIR
FILE1=${DIR}/infrastructure.properties
FILE2=${DIR}/testplan-props.properties
FILE3=run-intg-test.py
FILE4=configure_product.py
FILE5=const.py
FILE6=requirements.txt
FILE7=intg-test-runner.sh
FILE8=intg-test-runner.bat
FILE9=testng.xml
FILE10=testng-server-mgt.xml
FILE11=$wum_path

PROP_KEY=keyFileLocation      #pem file
PROP_OS=OS                       #OS name e.g. centos
PROP_JDK=JDK
PROP_DB=DBEngine
PROP_DIST_PROVIDED=DIST_PROVIDED
PROP_MODE=TEST_MODE

PROP_HOST=WSO2PublicIP           #host IP
PROP_INSTANCE_ID=WSO2InstanceId  #Physical ID (Resource ID) of WSO2 EC2 Instance

#----------------------------------------------------------------------
# getting data from databuckets
#----------------------------------------------------------------------
key_pem=`grep -w "$PROP_KEY" ${FILE1} ${FILE2} | cut -d'=' -f2`
os=`cat ${FILE2} | grep -w "$PROP_OS" ${FILE1} ${FILE2} | cut -d'=' -f2`
jdk=`cat ${FILE2} | grep -w "$PROP_JDK" ${FILE1} ${FILE2} | cut -d'=' -f2`
db=`cat ${FILE2} | grep -w "$PROP_DB" ${FILE1} ${FILE2} | cut -d'=' -f2`
dist_provided=`cat ${FILE2} | grep -w "$PROP_DIST_PROVIDED" ${FILE1} ${FILE2} | cut -d'=' -f2`
test_mode=`cat ${FILE2} | grep -w "$PROP_MODE" ${FILE1} ${FILE2} | cut -d'=' -f2`
#user=`cat ${FILE2} | grep -w "$PROP_USER" ${FILE1} ${FILE2} | cut -d'=' -f2`
instance_id=`cat ${FILE2} | grep -w "$PROP_INSTANCE_ID" ${FILE1} ${FILE2} | cut -d'=' -f2`
user=''
password=''
host=`grep -w "$PROP_HOST" ${FILE1} ${FILE2} | cut -d'=' -f2`
CONNECT_RETRY_COUNT=20

#=== FUNCTION ==================================================================
# NAME: request_ec2_password
# DESCRIPTION: Request password of Windows instance from AWS using the key file.
# PARAMETER 1: Physical-ID of the EC2 instance
#===============================================================================
request_ec2_password() {
  instance_id=$1
  echo "Retrieving password for Windows instance from AWS for instance id ${instance_id}"
  x=1;
  retry_count=$CONNECT_RETRY_COUNT;

  while [ "$password" == "" ] ; do
    #Request password from AWS
    responseJson=$(aws ec2 get-password-data --instance-id "${instance_id}" --priv-launch-key ${key_pem})

    #Validate JSON
    if [ $(echo $responseJson | python -c "import sys,json;json.loads(sys.stdin.read());print 'Valid'") == "Valid" ]; then
      password=$(python3 -c "import sys, json;print(($responseJson)['PasswordData'])")
      echo "Password received!"
    else
      echo "Invalid JSON response: $responseJson"
    fi

    if [ "$x" = "$retry_count" ]; then
      echo "Password never received for instance with id ${instance_id}. Hence skipping test execution!"
      exit
    fi

    sleep 10 # wait for 10 second before check again
    x=$((x+1))
  done
}

#=== FUNCTION ==================================================================
# NAME: wait_for_port
# DESCRIPTION: Check if the port is opened till the time-out occurs
# PARAMETER 1: Host name
# PARAMETER 2: Port number
#===============================================================================
wait_for_port() {
  host=$1
  port=$2
  x=1;
  retry_count=$CONNECT_RETRY_COUNT;
  echo "Wait port: ${1}:${2}"
  while ! nc -z $host $port; do
    sleep 2 # wait for 2 second before check again
    echo -n "."
    if [ $x = $retry_count ]; then
      echo "port never opened."
      exit 1
    fi
  x=$((x+1))
  done
}

#----------------------------------------------------------------------
# select default username and remote directory based on the OS
#----------------------------------------------------------------------
case "${os}" in
   "CentOS")
    	user=centos
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_UNIX ;;
   "Windows")
    	user=Administrator
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_WINDOWS ;;
   "UBUNTU")
        user=ubuntu
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_UNIX ;;
esac

REM_DIR=`grep -w "$PROP_REMOTE_DIR" ${FILE1} ${FILE2} | cut -d'=' -f2`

#----------------------------------------------------------------------
# wait till port 22 is opened for SSH
#----------------------------------------------------------------------
#wait_for_port ${host} 22

#----------------------------------------------------------------------
# execute commands based on the OS of the instance
# Steps followed;
# 1. SSH and make the directory.
# 2. Copy necessary files to the instance.
# 3. Execute scripts at the instance.
# 4. Retrieve reports from the instance.
#----------------------------------------------------------------------
if [ "${os}" = "Windows" ]; then
  echo "sp-integration tests for windows is not implemented because the undeline insfrastructure
        is kubernets"
else  
  prgdir=$(dirname "$0")
  cp ${DIR}/infrastructure.properties ${prgdir}/
  cp ${DIR}/testplan-props.properties ${prgdir}/

  bash ${prgdir}/intg-test-runner.sh --wd ${prgdir}
  unzip -q storage/*.zip -d ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/tmp/files/
  aws s3 sync s3://sp-docker-resources ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/tmp/files/

  
  ecr_login=$(aws ecr get-login)
  reg_user=$(echo $ecr_login | cut -d' ' -f4)
  reg_password=$(echo $ecr_login | cut -d' ' -f6)
  reg_url=$(echo $ecr_login | cut -d' ' -f9 | cut -d'/' -f3)

  echo "docker_server=$reg_url" > ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-registry.properties
  echo "docker_user=$reg_user" >> ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-registry.properties
  echo "docker_pw=$reg_password" >> ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-registry.properties

  cd ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/

  bash docker-create.sh ${test_mode} ${jdk} ${db} ${dist_provided}

  cd ${prgdir}

  #configure kubectl
  kube_id=${os}-${db}
  kube_id=$(echo "$kube_id" | sed 's/.*/\L&/')

  cp ~/.kube/config ~/.kube/config-"$kube_id"
  export KUBECONFIG=~/.kube/config-"$kube_id"

  kubectl create namespace "$kube_id"
  kube_context=$(kubectl config view -o=jsonpath="{$.current-context}")
  kube_cluster=$(kubectl config view -o=jsonpath="{$.contexts[?(@.name=='"$kube_context"')].context.cluster}")
  kube_user=$(kubectl config view -o=jsonpath="{$.contexts[?(@.name=='"$kube_context"')].context.user}")

  kubectl config set-context "$kube_id" --namespace="$kube_id" \
  --cluster="$kube_cluster" \
  --user="$kube_user"

  kubectl config use-context "$kube_id"
  kubectl config current-context

  cd ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration
  mvn clean install

  kubectl delete namespace "$kube_id"
  rm ~/.kube/config-"$kube_id"

  #copy the docker resources to correct location

  #Get the reports from integration test
  cp ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/target/surefire-reports ${prgdir}/
  cp ${prgdir}/product-sp/modules/integration/tests-kubernetes-integration/target/logs/automation.log ${prgdir}/
  cp ${prgdir}/storage/output.properties ${prgdir}/
  
#   scp -o StrictHostKeyChecking=no -r -i ${key_pem} ${user}@${host}:${REM_DIR}/product-sp/modules/integration/tests-kubernetes-integration/target/surefire-reports ${DIR}
#   scp -o StrictHostKeyChecking=no -r -i ${key_pem} ${user}@${host}:${REM_DIR}/product-apim/modules/integration/tests-integration/tests-backend/target/logs/automation.log ${DIR}
#   scp -o StrictHostKeyChecking=no -r -i ${key_pem} ${user}@${host}:${REM_DIR}/storage/output.properties ${DIR}
  echo "=== Reports are copied success ==="
fi
##script ends


