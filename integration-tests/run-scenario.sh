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
#set -o xtrace

DIR=/home/vasanthan/Downloads/sp/docker-sp/docker-sp/dockerfiles/base
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
echo "test mode is $test_mode"
echo "os is $os"
echo "username is $db_username"
echo "password is $db_password"


if [ "${test_mode}" = "RELEASE" ]
then
  git clone https://github.com/wso2/product-sp.git
  cd ${DIR}/product-sp/
  value=$(git for-each-ref --sort=taggerdate --format '%(refname) %(taggerdate)' refs/tags | tail -1 | cut -d "/" -f 3 | cut -d " " -f 1)
  git checkout tags/$value
elif  [ "${test_mode}" = "SNAPSHOT" ]
then
  git clone https://github.com/wso2/product-sp.git
else 
  echo "nothing matched"
fi


#resource downloading/copying
#TODO

#Database configuration

if [ "${db_url}" != "" ]
then

	DIR1=${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files
	echo "$DIR1"

	sed -i '/username:/ s/: .*/: '$db_username'/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml
	sed -i '/password:/ s/: .*/: '$db_password'/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml

	if [ "${db_type}" = "mysql" ]
	then
		sed -i '/jdbcUrl:/ s/: .*/: '$db_url'/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml 
		sed -i '/driverClassName:/ s/: .*/: com.mysql.jdbc.Driver/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml

	elif [ "${db_type}" = "oracle" ]
	then
		sed -i '/jdbcUrl:/ s/: .*/: '$db_url'/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml
		sed -i '/driverClassName:/ s/: .*/: oracle.jdbc.driver.OracleDriver/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml 
		sed -i '/connectionTestQuery:/ s/: .*/: SELECT 1 FROM DUAL/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml
 
	elif [ "${db_type}" = "mssql" ]
	then
		sed -i '/jdbcUrl:/ s/: .*/: '$db_url'/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml 
		sed -i '/driverClassName:/ s/: .*/: com.microsoft.sqlserver.jdbc.SQLServerDriver/' ${DIR1}/deployment-ha-node-1.yaml ${DIR1}/deployment-ha-node-2.yaml

	else
		echo "Nothing matched"
	fi
fi

#run docker-create
#sh ${DIR}/product-sp/modules/integration/tests-kubernetes-integration/src/test/resources/artifacts/docker-files/docker-create.sh ${test_mode}

#run mvn clean install
#cd ${DIR}/product-sp/modules/integration/tests-kubernetes-integration && mvn clean install








