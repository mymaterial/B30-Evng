## Create EC2 instance and configure aws in cli

EC2 -> Key Pairs -> Create Key Pair -> Name: pg-kp, Choose .ppk -> Finish

EC2 -> Launch Instance -> Name: my-inst 
    -> Image: ami-0e731c8a588258d0d (al2023-ami-2023.3.20240205.2-kernel-6.1-x86_64

![Minion](https://github.com/postgrestraining/B30-Evng/blob/main/images/EC2-us-east-1.png)

    -> Choose rest of the details -> Launch instance

## Login to the instance and do the following

    1. Set up AWSCLI
    2. Install Oracle Client
    3. Install PostgreSQL
    4. Setup postgres user environment variables
    5. Login as oracle user and create hr schema in AWS Oracle RDS instance

In Putty -> 
username : ec2-user@ec2-3-88-113-43.compute-1.amazonaws.com  
Credentials :  browse ppk

    



### Install AWSCLI

```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
/usr/local/bin/aws --version
```
Upon successful installation

```
[root@ip-10-1-1-250 ~]# /usr/local/bin/aws --version
aws-cli/2.15.21 Python/3.11.6 Linux/6.1.75-99.163.amzn2023.x86_64 exe/x86_64.amzn.2023 prompt/off
[root@ip-10-1-1-250 ~]#
```

### Configure oracle client

```
wget https://yum.oracle.com/RPM-GPG-KEY-oracle-ol8 -O /etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-oracle

yum install -y https://download.oracle.com/otn_software/linux/instantclient/1919000/oracle-instantclient19.19-basic-19.19.0.0.0-1.el9.x86_64.rpm

yum install -y https://download.oracle.com/otn_software/linux/instantclient/1919000/oracle-instantclient19.19-sqlplus-19.19.0.0.0-1.el9.x86_64.rpm

useradd oracle
su - oracle

sqlplus admin/oracle123@(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=orcl.cijxwe4ckz1m.us-east-1.rds.amazonaws.com)(PORT=1521)))(CONNECT_DATA=(SID=ORCL)))
```
Upon successful installation you should login to RDS instance

```
[oracle@ip-10-1-1-250 ~]$ sqlplus admin/oracle123@(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=orcl.cijxwe4ckz1m.us-east-1.rds.amazonaws.com)(PORT=1521)))(CONNECT_DATA=(SID=ORCL)))

SQL*Plus: Release 19.0.0.0.0 - Production on Sun Feb 18 17:12:44 2024
Version 19.19.0.0.0

Copyright (c) 1982, 2022, Oracle.  All rights reserved.


Connected to:
Oracle Database 19c Standard Edition 2 Release 19.0.0.0.0 - Production
Version 19.18.0.0.0

SQL>
```

## Configure hr schema in RDS

1. Download B30-Evng project to EC2 machine

```
wget https://github.com/postgrestraining/B30-Evng/archive/refs/heads/main.zip
unzip main.zip
cd B30-Evng-main
cd human_resources/
[oracle@ip-10-1-1-250 human_resources]$ pwd
/home/oracle/B30-Evng-main/human_resources
[oracle@ip-10-1-1-250 human_resources]$
```

2. Execute hr_main.sql

```

[oracle@ip-10-1-1-250 human_resources]$ sqlplus admin/oracle123@(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=orcl.cijxwe4ckz1m.us-east-1.rds.amazonaws.com)(PORT=1521)))(CONNECT_DATA=(SID=ORCL)))

SQL*Plus: Release 19.0.0.0.0 - Production on Sun Feb 18 17:23:23 2024
Version 19.19.0.0.0

Copyright (c) 1982, 2022, Oracle.  All rights reserved.

Last Successful login time: Sun Feb 18 2024 17:12:44 +00:00

Connected to:
Oracle Database 19c Standard Edition 2 Release 19.0.0.0.0 - Production
Version 19.18.0.0.0

SQL> @hr_main.sql

specify password for HR as parameter 1:
Enter value for 1: oracle

specify default tablespeace for HR as parameter 2:
Enter value for 2: USERS

specify temporary tablespace for HR as parameter 3:
Enter value for 3: TEMP

specify log path as parameter 4:
Enter value for 4: /home/oracle/

..
..
1 row created.


1 row created.

Commit complete.
```

## Install PostgreSQL Client

```
useradd postgres
dnf install postgresql15.x86_64 postgresql15-server -y

[ec2-user@ip-10-1-1-250 ~]$ sudo su
[root@ip-10-1-1-250 ec2-user]# cd
[root@ip-10-1-1-250 ~]# useradd postgres
[root@ip-10-1-1-250 ~]# dnf install postgresql15.x86_64 postgresql15-server -y
..
..
Complete!
[root@ip-10-1-1-250 ~]# su - postgres
[postgres@ip-10-1-1-250 ~]$
```

## Configure awscli in postgres user

-> Create security credentials and notedown AWS Access Key ID and AWS Secret Access Key

```
[postgres@ip-10-1-1-250 ~]$ aws configure
AWS Access Key ID [None]: XXXXXXXX
AWS Secret Access Key [None]: XXXXXXXX
Default region name [None]: us-east-1
Default output format [None]:
[postgres@ip-10-1-1-250 ~]$
```

## set up environment variables

```
cd /home/postgres/B30-Evng-main/db
sh setup-env.sh us-east-1
sh set-endpoints.sh pg-rdsa-cluster

Sample output should look like and look for entries in /home/postgres/.bashrc

[postgres@ip-10-1-1-250 db]$ sh set-endpoints.sh rdsa-postgresql-cluster
PGWRITEREP=rdsa-postgresql-cluster.cluster-cijxwe4ckz1m.us-east-1.rds.amazonaws.com
PGREADEREP=rdsa-postgresql-cluster.cluster-ro-cijxwe4ckz1m.us-east-1.rds.amazonaws.com
[postgres@ip-10-1-1-250 db]$
```

## Parameter Groups

DB instance parameter group:  default.aurora-postgresql15
DB cluster parameter group: default.aurora-postgresql15

```
export PG_CLUSTER_ID=pg-rdsa-cluster
sh create-custom-db-cluster-pg.sh pg-rdsa-cluster-pg pg-rdsa-cluster-pg
sh create-custom-db-pg.sh pg-rdsa-instance-pg pg-rdsa-instance-pg
sh set-parameter-value.sh pg-rdsa-cluster-pg session_replication_role replica
sh set-instance-parameter-value.sh pg-rdsa-instance-pg session_replication_role replica
```

## apply changes

```
aws rds modify-db-instance \
--db-instance-identifier  pg-rdsa-node-01 \
--db-parameter-group-name pg-rdsa-instance-pg \
--apply-immediately

aws rds modify-db-cluster \
--db-cluster-identifier pg-rdsa-cluster \
--db-cluster-parameter-group-name pg-rdsa-cluster-pg \
--apply-immediately
```

Reboot the cluster 
```
aws rds reboot-db-instance --db-instance-identifier  pg-rdsa-node-01
```



