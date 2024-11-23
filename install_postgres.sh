#!/bin/bash

# 该脚本只能在 /mnt 运行哦 其他兼容还在优化
user="postgres"
home="/home/postgres"
tar="postgresql-10.22.tar.gz"
pwd=$(pwd)
package_url="https://ftp.postgresql.org/pub/source/v10.22/$tar"
result=$(cat /etc/passwd | grep $user | awk -F: '{print $1}')

# 下载一些依赖
yum -y install zlib zlib-devel cracklib-devel readline-devel gcc


# 检查redis压缩包是否已经存在  
if [ ! -f "$tar" ]; then
    # 如果不存在，下载  
    echo "1.正在下载postgres压缩包..."  
    wget "$package_url"
# $? 是用来检测上个上个命令推出状态的 -ne 是不等于的意思 这里就是不等于0
    if [ $? -ne 0 ]; then
        echo "下载postgres压缩包失败"  
        exit 1
    fi
else
    echo "poatgres压缩包已存在"  
fi


# 创建postgres用户
if [[ "$result" == "$user" ]]; then
    echo "postgres 用户已存在"
    chown -R $user:$user $postgres /mnt/postgresql*
    echo "3.已刷新postgres权限"

else
    useradd $user
# 检测是否创建成功
   if [ $? -ne 0 ]; then
       echo "创建 postgres 用户失败"
       exit 1
   else
       chown -R $user:$user $postgres_DIR /mnt/postgres*
       echo "3.postgres用户创建成功并刷新权限"
   fi
fi


sudo -u $user cp postgresql-10.22.tar.gz $home
cd $home
pwd


if [ -f "$tar" ]; then 
       sudo -u $user tar -vxf postgresql-10.22.tar.gz  > tar.log 2>&1
else
        sudo -u $user cp $pwd/postgresql-10.22.tar.gz $home
        sudo -u $user tar -vxf postgresql-10.22.tar.gz  > tar.log 2>&1
fi

sudo -u $user mkdir -p $home/pgsql
cd $home/postgresql-10.22
pwd

if [ -f "$home/postgresql-10.22/prefix.log" ]; then 
        echo "已有编译日志，判断已经编译"

else
        #echo "make clean ing..."
        #sudo -u $user make clean 
        #if [ $? -ne 0 ]; then
        #        echo "make clean error"
        #        exit 1
        #else
        #        echo "make clean ok"        
        #fi
ls -al  $home/postgresql-10.22/prefix.log
        echo "prefix ing..."
        sudo -u $user ./configure --prefix=$home/pgsql > prefix.log 2>&1
        if [ $? -ne 0 ]; then
                echo "prefix error"
                exit 1
        else
                echo "prefix ok"
        fi
        chown $user:$user -R $home

        echo "make ing..."
        sudo -u $user make > make.log 2>&1 
        if [ $? -ne 0 ]; then
                echo "make error"
                exit 1
        else
                echo "make ok"
        fi
        chown $user:$user -R $home

        echo "make install ing..."
        sudo -u $user make install 
        #sudo -u $user make install > make install.log 2>&1
        if [ $? -ne 0 ]; then
                echo "make install error"
                exit 1
        else
                echo "make install ok"
        fi
        chown $user:$user -R $home


        sudo -u $user mkdir -p  $home/pgsqldata
        sudo -u $user mkdir -p $home/pgsqldata/data/
        sudo -u $user mkdir -p $home/pgsqldata/logs

        sudo -u $user echo 'PATH=$PATH:$HOME/.local/bin:$HOME/bin:$HOME/pgsql/bin' >> $home/.bash_profile
        sudo -u $user echo 'export PGhome=$HOME/pgsql' >> $home/.bash_profile
        sudo -u $user echo 'export PGDATA=$HOME/pgsqldata/data/' >> $home/.bash_profile
        sudo -u $user echo 'export PATH' >> $home/.bash_profile

        sudo -u $user source $home/.bash_profile
fi

cd $home/pgsql/bin

sudo -u $user ./initdb -D $home/pgsqldata/data


if [ -f "$home/pgsqldata/data/postgresql.conf" ]; then 
        echo "数据库已经初始化"
        echo "请执行cd $home/pgsql/bin"
        echo "记得切换postgres用户哦root不给启 sudo -u postgres bash "
        echo "执行  ./pg_ctl -D /home/postgres/pgsqldata/data -l logfile start"
        
else
        cd $home/pgsql/bin
        sudo -u $user ./initdb -D $home/pgsqldata/data
fi
