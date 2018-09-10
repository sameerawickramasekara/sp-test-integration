
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

db_type=$1
db_host=$2
db_username=$3
db_password=$4



if [ "${db_type}" = "mysql" ]
then
	mysql -h ${db_host} -P 3306 -u ${db_username} -p${db_password} -Bse "CREATE DATABASE WSO2_ANALYTICS_DB_SP;SHOW DATABASES;"

elif [ "${db_type}" = "oracle" ]
then

sqlplus64 ''${db_username}'/'${db_password}'@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST='${db_host}') (PORT=1521))(CONNECT_DATA=(SID=ora12c))) as sysdba'  <<EOF
	alter session set container=pdbora12c;
	drop user WSO2_ANALYTICS_DB_SP cascade;
	create user WSO2_ANALYTICS_DB_SP identified by ora12c ACCOUNT unlock;
	grant connect to WSO2_ANALYTICS_DB_SP;
	grant create session, create table, create sequence, create trigger to WSO2_ANALYTICS_DB_SP;
	grant all privileges to WSO2_ANALYTICS_DB_SP;
	ALTER USER WSO2_ANALYTICS_DB_SP quota unlimited on USERS;
	commit;
	exit;	
EOF
	

elif [ "${db_type}" = "mssql" ]
then
	sqlcmd -S ${db_host} -U ${db_username} -P ${db_password} -Q "CREATE DATABASE WSO2_ANALYTICS_DB_SP;EXEC sys.sp_databases"

else 
	echo "DB type not matched"
fi
