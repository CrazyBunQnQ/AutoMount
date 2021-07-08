#!/bin/bash

# 目录配置
bakDir=/root/csabak
fstabFile=/etc/fstab

# test
# fstabFile=/root/fstab.bak

# mysql 状态
csaon=1
mysqlon=1
# 大前提: 母盘 SSD 系统硬盘中已存在基础态势系统目录
if [ ! -d "$bakDir" ]; then
  if [ ! -d "/csa" ]; then
    echo "/csa" 目录不存在
    exit 1
  fi
  echo "停止 mysql 和 csa 服务..."
  sudo service mysql stop
  sudo service csa stop
  # 杀掉所有 java 相关进程
  sudo kill -9 $(ps -ef | grep java | grep -v grep | awk '{print$2}')
  mysqlon=0
  csaon=0
  echo "$bakDir 备份目录不存在, 创建备份目录: sudo cp -rp /csa $bakDir"
  sudo cp -rp /csa $bakDir
  # 不能删除文件夹，每个文件夹都有权限，而且权限不一定相同, 具体权限可以查看 /csa/component/*.yml 配置
  sudo rm -f $bakDir/applog/**/*.log
fi
# 情况一: /csa 是 SSD 系统盘的一个目录
#         需要检测其他硬盘，且挂载硬盘分区 /dev/xxx 到 /csa 目录, 且写入 /etc/fstab
#         并且要将服务拷贝过去
# 情况二: /csa 已挂载到其他硬盘上
#         需要检测挂载正常，不正常需要修复

# 判断属于情况一还是情况二
scene=1
tmp=$(df -h | grep -c " /csa")
if [ $tmp -eq 0 ]; then
  echo "当前 /csa 目录在系统盘"
  scene=1
else
  # 查看当前 /csa 挂载的是什么目录
  curMount=$(df -h | grep /csa | awk '{print$1}')
  echo "当前 /csa 挂载的目录为 $curMount, 是非系统盘"
  # 校验磁盘是否存在, 已存在则系统正常
  if [ $(fdisk -l | grep -c "$curMount ") -gt 0 ]; then
    echo "磁盘挂载正常"
    if [ $mysqlon -eq 0 ]; then
      echo "启动 mysql 服务"
      sudo service mysql start
    fi
    if [ $csaon -eq 0 ]; then
      echo "启动 csa 服务"
      sudo service csa start
    fi
    exit 0
  fi
  scene=2
fi

# 不同情况不同处理
if [ $scene -eq 1 ]; then
  # TODO 只取排除系统盘后的第一条结果
  diskName=$(fdisk -l | grep "Disk /dev/" | grep " TiB" | awk '{print$2}')
  # 不存在的话直接结束
  if [ "$diskName" = "" ]; then
    echo "不存在额外硬盘，继续使用系统盘"
    if [ $mysqlon -eq 0 ]; then
      echo "启动 mysql 服务"
      sudo service mysql start
    fi
    if [ $csaon -eq 0 ]; then
      echo "启动 csa 服务"
      sudo service csa start
    fi
    exit 1
  fi
  echo "开始迁移应用到大容量硬盘中...备份 /etc/fstab 到 /root/fstab.bak"
  sudo cp /etc/fstab /root/fstab.bak
  if [ $mysqlon -eq 1 ]; then
    echo "停止 mysql 服务..."
    sudo service mysql stop
    mysqlon=0
  fi
  if [ $mysqlon -eq 1 ]; then
    echo "停止 csa 服务..."
    sudo service csa stop
    csaon=0
  fi
  mysqlon=0
  csaon=0
  diskName=${diskName%:}
  echo "获取超过 1T 的磁盘名称: $diskName"
  # 分区, 整块磁盘分一个区
  echo "标记磁盘: sudo parted $diskName mklabel gpt"
  sudo parted $diskName mklabel gpt
  echo "磁盘分区: sudo parted $diskName mkpart primary 2048s 100%"
  sudo parted $diskName mkpart primary 2048s 100%
  echo "分区结果:"
  sudo parted $diskName p
  # 查看空间上 T 的分区
  dir=$(fdisk -l | grep -A 3 "Device " | grep "T " | awk '{print$1}')
  lastDir="/${dir##*/}"
  echo "全目录: $dir, 最终目录名: $lastDir"
  # 分区格式化
  echo "分区格式化: sudo mkfs.ext4 $dir"
  sudo mkfs.ext4 $dir
  echo "清空原 /csa 目录..."
  sudo rm -rf /csa/*
  # 挂载分区到 /csa
  echo "挂载分区 $dir 到 /csa: sudo mount $dir /csa/"
  sudo mount $dir /csa/
  # 删除员 fstab 挂载 /csa 配置
  if [ $(cat $fstabFile | grep -c " /csa ") -gt 0 ]; then
    # 若当前 /etc/fstab 是否已配置 /csa 则删除该行
    echo "当前 $fstabFile 中已存在 /csa 配置, 删除已有配置:"
    tmp=$(cat $fstabFile | grep " /csa ")
    # echo $tmp
    sed -i '/ \/csa /d' $fstabFile
  fi
  # 校验磁盘挂载状态
  tmp2=$(df -h | grep -c " /csa")
  if [ $tmp2 -gt 0 ]; then
    # 查看磁盘 uuid
    uuid=$(ls -l /dev/disk/by-uuid | grep $lastDir | awk '{print$9}')
    echo "挂载 $lastDir 成功, uuid:  $uuid"
    # 写入挂载配置
    echo "写入挂载配置: echo \"/dev/disk/by-uuid/$uuid /csa ext4 defaults 0 0\" >> $fstabFile"
    echo "/dev/disk/by-uuid/$uuid /csa ext4 defaults 0 0" >> $fstabFile
  else
    echo "$dir 硬盘挂载失败!!!"
  fi
  sudo rm -rf /csa/*
  echo "拷贝服务到 /csa 目录并授权: sudo cp -rp $bakDir/* /csa/"
  sudo cp -rp $bakDir/* /csa/
  echo "启动 csa 服务"
  sudo service csa start
  # cat $fstabFile
else
  echo "情况二: /csa 挂载到非系统盘中但是挂载异常"
fi

