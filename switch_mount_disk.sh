# 目录配置
bakDir=/root/csabak
fstabFile=/etc/fstab

# test
fstabFile=/root/fstab.bak

# 大前提: 母盘 SSD 系统硬盘中已存在基础态势系统目录
if [ ! -d "$bakDir" ]; then
  if [ ! -d "/csa" ]; then
    echo "/csa" 目录不存在
    exit 1
  fi
  echo "$bakDir 备份目录不存在, 创建备份目录..."
  sudo cp -r /csa $bakDir
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
  echo "当前 /csa 目录系统盘"
  scene=1
else
  # 查看当前 /csa 挂载的是什么目录
  curMount=$(df -h | grep /csa | awk '{print$1}')
  echo "当前 /csa 挂载的目录为 $curMount, 是非系统盘"
  # 校验磁盘是否存在, 已存在则系统正常
  if [ $(fdisk -l | grep -c "$curMount ") -gt 0 ]; then
    echo "磁盘挂载正常"
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
    exit 1
  fi
  diskName=${diskName%:}
  echo "获取超过 1T 的磁盘名称: $diskName"
  # TODO 分区, 整块磁盘分一个区
  echo "磁盘分区: sudo parted $diskName mkpart primary 2048s 100%"
  # sudo parted $diskName mkpart primary 2048s 100%
  # 查看空间上 T 的分区
  dir=$(fdisk -l | grep -A 3 "Device " | grep "T " | awk '{print$1}')
  echo "全目录: $dir"
  lastDir="/${dir##*/}"
  echo "最终目录名: $lastDir"
  # TODO 分区格式化
  echo "分区格式化: sudo mkfs.ext4 $dir"
  # sudo mkfs.ext4 $dir
  echo "清空原 /csa 目录..."
  sudo rm -rf /csa/*
  # TODO 挂载分区到 /csa
  echo "挂载分区 $dir 到 /csa: sudo mount $dir /csa/"
  # sudo mount $dir /csa/
  # 查看磁盘 uuid
  uuid=$(ls -l /dev/disk/by-uuid | grep $lastDir | awk '{print$9}')
  echo "$lastDir 的磁盘 uuid:  $uuid"
  # 写入挂载配置
  if [ $(cat $fstabFile | grep -c " /csa ") -gt 0 ]; then
    # 若当前 /etc/fstab 是否已配置 /csa 则删除该行
    echo "当前 $fstabFile 中已存在 /csa 配置, 删除已有配置:"
    tmp=$(cat $fstabFile | grep " /csa ")
    echo $tmp
    sed -i '/ \/csa /d' $fstabFile
  fi
  echo "写入挂载配置: echo \"/dev/disk/by-uuid/$uuid /csa ext4 defaults 0 0\" >> $fstabFile"
  echo "/dev/disk/by-uuid/$uuid /csa ext4 defaults 0 0" >> $fstabFile
  echo "拷贝服务到 /csa 目录"
  cp -r /root/csa/* /csa/*
else
  echo "情况二: /csa 挂载到非系统盘中但是挂载异常"
fi
