#!/bin/bash
cat << "EOF" | tee /etc/apt/sources.list
# deb http://deb.debian.org/debian/ bullseye main
# deb-src http://deb.debian.org/debian/ bullseye main
# deb http://security.debian.org/debian-security bullseye-security main contrib
# deb-src http://security.debian.org/debian-security bullseye-security main contrib
# deb http://deb.debian.org/debian/ bullseye-updates main contrib
# deb-src http://deb.debian.org/debian/ bullseye-updates main contrib

deb http://deb.debian.org/debian bullseye main contrib non-free
deb-src http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian-security bullseye-security/updates main contrib non-free
deb-src http://deb.debian.org/debian-security bullseye-security/updates main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb-src http://deb.debian.org/debian bullseye-updates main contrib non-free

deb http://deb.debian.org/debian bullseye-backports main contrib non-free
deb-src http://deb.debian.org/debian bullseye-backports main contrib non-free
EOF

apt update && apt full-upgrade -y
apt install -t bullseye-backports zfs-dkms -y
apt install -y wget vim curl dnsutils net-tools ifupdown2 vlan ifenslave sudo snapd zfsutils-linux chrony libnftables-dev libprotobuf-dev libprotobuf-c-dev protobuf-c-compiler protobuf-compiler python3-protobuf libnet1-dev linux-headers-5.18.0-0.bpo.1-amd64 linux-image-5.18.0-0.bpo.1-amd64

echo 'bonding' >> /etc/modules 
echo '8021q' >> /etc/modules
/sbin/modprobe 8021q
/sbin/modprobe bonding

systemctl enable --now snapd

wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

gpg --no-default-keyring \
    --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    --fingerprint

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list



cat << EOF | tee /etc/ssh/sshd_config
Include /etc/ssh/sshd_config.d/*.conf
PasswordAuthentication no 
ChallengeResponseAuthentication no
HostKey /etc/ssh/ssh_host_ed25519_key
LoginGraceTime 60
#ListenAddress 0.0.0.0
MaxStartups 200
PermitRootLogin prohibit-password
StrictModes yes
PermitEmptyPasswords no
PubkeyAuthentication yes
PrintMotd no
RekeyLimit 1G 1300
Ciphers chacha20-poly1305@openssh.com
HostKeyAlgorithms ssh-ed25519
MACs umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256@libssh.org
UsePAM yes
X11Forwarding no
PrintMotd no
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

systemctl enable ssh;
systemctl restart ssh;
chmod 600 /etc/sudoers
echo "ops ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers
chmod 400 /etc/sudoers

for i in $(ls /dev | grep ceph); do rm -rf /dev/$i; done
wipefs -af /dev/sda
wipefs -af /dev/nvme0n1

snap refresh
snap install core20
snap install core22
snap install lxd --channel=latest
snap set lxd criu.enable=true

cat << "EOF" | sudo tee -a /etc/security/limits.conf
*               soft    nofile            1048576
*               hard    nofile            1048576
root            soft    nofile            1048576
root            hard    nofile            1048576
*               soft    memlock           unlimited
*               hard    memlock           unlimited
root            soft    memlock           unlimited
root            hard    memlock           unlimited
EOF

cat << "EOF" | sudo tee -a /etc/sysctl.conf
fs.aio-max-nr = 524288
fs.inotify.max_queued_events = 1048576
fs.inotify.max_user_instances = 1048576
fs.inotify.max_user_watches = 1048576
kernel.dmesg_restrict = 1
kernel.keys.maxbytes = 2000000
kernel.keys.maxkeys = 2000
net.ipv4.neigh.default.gc_thresh3 = 8192
net.ipv6.neigh.default.gc_thresh3 = 8192
vm.max_map_count = 262144
EOF

chmod 400 /proc/sched_debug
chmod 700 /sys/kernel/slab/

cat << EOF | sudo tee -a /etc/hosts
172.16.16.1 alpha
172.16.16.2 beta
172.16.16.3 gamma
172.16.16.4 delta
172.16.16.5 epsilon
EOF
