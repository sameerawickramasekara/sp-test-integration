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

set -e
set -o xtrace

DIR=$2
FILE1=${DIR}/infrastructure.properties
FILE2=${DIR}/testplan-props.properties


PROP_OS=OS                       #OS name e.g. centos
PROP_TEST_MODE=TEST_MODE
PROP_DB_URL=DatabaseHost
PROP_DB_TYPE=DBEngine
PROP_PRODUCT_URL=PRODUCT_GIT_URL
JDK=JDK
CUSTOM_PACK=CUSTOM_PACK
CUSTOM_TAG=CUSTOM_TAG
PROP_DB_UN=db_username
PROP_DB_PW=db_password
K8S_MASTER=K8S_MASTER

os=`cat ${FILE2} | grep -w "$PROP_OS" ${FILE1} ${FILE2}| cut -d'=' -f2`
test_mode=`cat ${FILE2} | grep -w "$PROP_TEST_MODE" ${FILE1} ${FILE2}| cut -d'=' -f2`
db_url=`cat ${FILE2} | grep -w "$PROP_DB_URL" ${FILE1} | cut -d'=' -f2`
db_type=`cat ${FILE2} | grep -w "$PROP_DB_TYPE" ${FILE1} ${FILE2} | cut -d'=' -f2`
db_username=`cat ${FILE2} | grep -w "$PROP_DB_UN" ${FILE1} ${FILE2} | cut -d'=' -f2`
db_password=`cat ${FILE2} | grep -w "$PROP_DB_PW" ${FILE1} ${FILE2} | cut -d'=' -f2`
jdk=`cat ${FILE2} | grep -w "$JDK" ${FILE1} ${FILE2} | cut -d'=' -f2`
custom_pack=`cat ${FILE2} | grep -w "$CUSTOM_PACK" ${FILE1} ${FILE2} | cut -d'=' -f2`
custom_tag=`cat ${FILE2} | grep -w "$CUSTOM_TAG" ${FILE1} ${FILE2} | cut -d'=' -f2`
k8s_master=`cat ${FILE2} | grep -w "$K8S_MASTER" ${FILE1} ${FILE2} | cut -d'=' -f2`
product_url=`cat ${FILE2} | grep -w "$PROP_PRODUCT_URL" ${FILE1} ${FILE2} | cut -d'=' -f2`
#
echo "Db type is $db_type"
echo "Db_url is $db_url"
echo "test mode is $test_mode"
echo "os is $os"
echo "username is $db_username"
echo "password is $db_password"
echo "custom pack $custom_pack"

git clone https://github.com/wso2/product-sp.git ${DIR}/product-sp

if [ "${test_mode}" = "RELEASE" ]
then
  cd ${DIR}/product-sp/
  value=$(git for-each-ref --sort=taggerdate --format '%(refname) %(taggerdate)' refs/tags | tail -1 | cut -d "/" -f 3 | cut -d " " -f 1)
  git checkout tags/$value
fi


#resource downloading/copying
resource_path=${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/tmp/files/
mkdir -p $resource_path
aws s3 sync s3://sp-docker-resources $resource_path

#unzip and remove correct jdk
unzip -q $resource_path/jdk*.zip -d $resource_path
rm $resource_path/jdk*.zip
#configure databases
bash ${DIR}/integration-tests/db-config.sh ${db_type} ${db_url} ${db_username} ${db_password}

#Database configuration

#set docker login data

login_data=$(aws ecr get-login)
docker_username=$(echo "$login_data" |  cut -d" " -f4)
docker_password=$(echo "$login_data" |  cut -d" " -f6)
docker_server=$(echo "$login_data" |  cut -d" " -f9 | cut -d"/" -f3)


echo "docker_user="$docker_username > ${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-registry.properties
echo "docker_pw="$docker_password >> ${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-registry.properties
echo "docker_server="$docker_server >> ${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-registry.properties

echo "KUBERNETES_MASTER=$k8s_master" > ${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/infrastructure-automation/k8s.properties
#
##Database configuration
#
if [ "${db_url}" != "" ]
then

	DOCKER_FILES_DIR=${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files

	sed -i '/username:/ s/: .*/: '$db_username'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
	sed -i '/password:/ s/: .*/: '$db_password'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml

	if [ "${db_type}" = "mysql" ]
	then
		sed -i '/jdbcUrl:/ s/: .*/: jdbc:mysql:\/\/'$db_url'\/WSO2_ANALYTICS_DB?useSSL=false/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/driverClassName:/ s/: .*/: com.mysql.jdbc.Driver/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml

	elif [ "${db_type}" = "oracle" ]
	then
		sed -i '/jdbcUrl:/ s/: .*/: jdbc:oracle:thin:@'$db_url':1521:ORCL/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/driverClassName:/ s/: .*/: oracle.jdbc.driver.OracleDriver/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/connectionTestQuery:/ s/: .*/: SELECT 1 FROM DUAL/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
 
	elif [ "${db_type}" = "mssql" ]
	then
		sed -i '/jdbcUrl:/ s/: .*/: jdbc:sqlserver:\/\/'$db_url':1433;databaseName=WSO2_ANALYTICS_DB/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/driverClassName:/ s/: .*/: com.microsoft.sqlserver.jdbc.SQLServerDriver/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml

	else
		echo "DB type is not matched"
	fi
fi

#run docker-create
bash ${DOCKER_FILES_DIR}/docker-create.sh ${test_mode} ${jdk} ${db_type} ${custom_pack}

#clear docker resources from repository workspace
rm -rf $resource_path/*

#run mvn clean install
cd ${DIR}/product-sp/modules/integration/tests-kubernetes-integration && mvn clean install








