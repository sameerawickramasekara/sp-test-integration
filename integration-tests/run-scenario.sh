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
PROP_DB_UN=db_username
PROP_DB_PW=db_password

os=`cat ${FILE2} | grep -w "$PROP_OS" ${FILE1} ${FILE2}| cut -d'=' -f2`
test_mode=`cat ${FILE2} | grep -w "$PROP_TEST_MODE" ${FILE1} ${FILE2}| cut -d'=' -f2`
db_url=`cat ${FILE2} | grep -w "$PROP_DB_URL" ${FILE1} | cut -d'=' -f2`
db_type=`cat ${FILE2} | grep -w "$PROP_DB_TYPE" ${FILE1} ${FILE2} | cut -d'=' -f2`
db_username=`cat ${FILE2} | grep -w "$PROP_DB_UN" ${FILE1} ${FILE2} | cut -d'=' -f2`
db_password=`cat ${FILE2} | grep -w "$PROP_DB_PW" ${FILE1} ${FILE2} | cut -d'=' -f2`

echo "Db type is $db_type"
echo "Db_url is $db_url"
echo "Test mode is $test_mode"
echo "OS is $os"
echo "Username is $db_username"
echo "Password is $db_password"


INTG_TEST_DIR=$(cd `dirname $0` && pwd)

git clone https://github.com/wso2/product-sp.git ${DIR}/product-sp

if [ "${test_mode}" = "RELEASE" ]
then
  cd ${DIR}/product-sp/
  value=$(git for-each-ref --sort=taggerdate --format '%(refname) %(taggerdate)' refs/tags | tail -1 | cut -d "/" -f 3 | cut -d " " -f 1)
  git checkout tags/$value
fi



#resource downloading/copying
#TODO

#configure databases
cd ${INTG_TEST_DIR}
pwd
bash db-config.sh ${db_type} ${db_url} ${db_username} ${db_password}

#Database configuration

if [ "${db_url}" != "" ]
then

	DOCKER_FILES_DIR=${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files
	
	sed -i '/name: WSO2_CARBON_DB/,/username:.*/s/username:.*/username: '${db_username}'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
	sed -i '/name: WSO2_CARBON_DB/,/password:.*/s/password:.*/password: '${db_password}'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml

	if [ "${db_type}" = "mysql" ]
	then
		sed -i '/name: WSO2_CARBON_DB/,/jdbcUrl:.*/s/jdbcUrl:.*/jdbcUrl: 'jdbc:mysql:\\/\\/${db_url}\\/WSO2_ANALYTICS_DB_SP?useSSL=false'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/name: WSO2_CARBON_DB/,/driverClassName:.*/s/driverClassName:.*/driverClassName: com.mysql.jdbc.Driver/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml

	elif [ "${db_type}" = "oracle" ]
	then
		sed -i '/name: WSO2_CARBON_DB/,/jdbcUrl:.*/s/jdbcUrl:.*/jdbcUrl: 'jdbc:oracle:thin:${db_url}:1521:ORCL'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/name: WSO2_CARBON_DB/,/driverClassName:.*/s/driverClassName:.*/driverClassName: oracle.jdbc.driver.OracleDriver/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/name: WSO2_CARBON_DB/,/connectionTestQuery:.*/s/connectionTestQuery:.*/connectionTestQuery: SELECT 1 FROM DUAL/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
 
	elif [ "${db_type}" = "mssql" ]
	then
		sed -i '/name: WSO2_CARBON_DB/,/jdbcUrl:.*/s/jdbcUrl:.*/jdbcUrl: 'jdbc:sqlserver:\\/\\/${db_url}:1433\;databaseName=WSO2_ANALYTICS_DB_SP'/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml
		sed -i '/name: WSO2_CARBON_DB/,/driverClassName:.*/s/driverClassName:.*/driverClassName: com.microsoft.sqlserver.jdbc.SQLServerDriver/' ${DOCKER_FILES_DIR}/deployment-ha-node-1.yaml ${DOCKER_FILES_DIR}/deployment-ha-node-2.yaml

	else
		echo "DB type is not matched"
	fi
fi

#run docker-create
sh ${DOCKER_FILES_DIR}/docker-create.sh ${test_mode}

#run mvn clean install
cd ${DIR}/product-sp/modules/integration/tests-kubernetes-integration && mvn clean install








