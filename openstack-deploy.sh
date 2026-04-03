#!/bin/bash
#######################################################################
# OpenStack Train 一键部署脚本
# 适用系统: CentOS 7
# 部署版本: OpenStack Train
# 作者: NingchenNingchen
# 说明: 此脚本用于一键部署完整的OpenStack私有云平台
#       支持控制节点和计算节点自动识别
#######################################################################

set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== 日志函数 ====================
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# ==================== 全局配置 ====================
# 网络配置
CONTROLLER_IP="192.168.100.10"
COMPUTE_IP="192.168.100.20"
CONTROLLER_HOST="controller"
COMPUTE_HOST="compute1"

# 密码配置
DB_PASSWORD="openstack"
RABBIT_PASSWORD="openstack"
ADMIN_PASSWORD="admin"
KEYSTONE_PASSWORD="openstack"
GLANCE_PASSWORD="openstack"
NOVA_PASSWORD="openstack"
PLACEMENT_PASSWORD="openstack"
NEUTRON_PASSWORD="openstack"
CINDER_PASSWORD="openstack"

# 节点类型
NODE_TYPE=""

# ==================== 函数定义 ====================

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root用户运行此脚本"
        exit 1
    fi
}

# 选择节点类型
select_node_type() {
    echo ""
    echo "=========================================="
    echo "  OpenStack Train 一键部署脚本"
    echo "=========================================="
    echo ""
    echo "请选择节点类型："
    echo "  1) 控制节点 (Controller)"
    echo "  2) 计算节点 (Compute)"
    echo ""
    read -p "请输入选项 [1-2]: " choice
    
    case $choice in
        1)
            NODE_TYPE="controller"
            log_info "已选择: 控制节点"
            ;;
        2)
            NODE_TYPE="compute"
            log_info "已选择: 计算节点"
            ;;
        *)
            log_error "无效的选项，请重新运行脚本"
            exit 1
            ;;
    esac
}

# ==================== 第一步：基础环境配置 ====================

# 配置主机名
configure_hostname() {
    log_step "配置主机名..."
    
    if [ "$NODE_TYPE" == "controller" ]; then
        hostnamectl set-hostname $CONTROLLER_HOST
    else
        hostnamectl set-hostname $COMPUTE_HOST
    fi
    
    log_info "主机名配置完成: $(hostname)"
}

# 配置域名解析
configure_hosts() {
    log_step "配置域名解析..."
    
    cat >> /etc/hosts <<EOF
$CONTROLLER_IP $CONTROLLER_HOST
$COMPUTE_IP $COMPUTE_HOST
EOF
    
    log_info "域名解析配置完成"
}

# 配置YUM源
configure_yum() {
    log_step "配置YUM源（阿里云镜像）..."
    
    # 备份原有YUM源
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
    
    # 创建OpenStack.repo
    cat > /etc/yum.repos.d/OpenStack.repo <<'EOF'
[yuan-base]
name=yuan-base
baseurl=http://mirrors.aliyun.com/centos/7/os/x86_64/
gpgcheck=0
enabled=1

[yuan-updates]
name=yuan-updates
baseurl=http://mirrors.aliyun.com/centos/7/updates/x86_64/
gpgcheck=0
enabled=1

[yuan-extras]
name=yuan-extras
baseurl=http://mirrors.aliyun.com/centos/7/extras/x86_64/
gpgcheck=0
enabled=1

[yuan-train]
name=yuan-train
baseurl=http://mirrors.aliyun.com/centos/7/cloud/x86_64/openstack-train/
gpgcheck=0
enabled=1

[yuan-virt]
name=yuan-virt
baseurl=http://mirrors.aliyun.com/centos/7/virt/x86_64/kvm-common/
gpgcheck=0
enabled=1
EOF
    
    yum clean all
    yum makecache
    
    log_info "YUM源配置完成"
}

# 关闭防火墙和SELinux
disable_security() {
    log_step "关闭防火墙和SELinux..."
    
    # 关闭防火墙
    systemctl stop firewalld
    systemctl disable firewalld
    
    # 关闭SELinux
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    
    log_info "安全策略配置完成"
}

# 配置时间同步
configure_ntp() {
    log_step "配置时间同步..."
    
    if [ "$NODE_TYPE" == "controller" ]; then
        # 控制节点配置为NTP服务器
        cat > /etc/chrony.conf <<EOF
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
allow 192.168.100.0/24
local stratum 1
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF
    else
        # 计算节点向控制节点同步
        cat > /etc/chrony.conf <<EOF
server $CONTROLLER_HOST iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF
    fi
    
    systemctl restart chronyd
    systemctl enable chronyd
    
    log_info "时间同步配置完成"
}

# 安装基础工具
install_basic_tools() {
    log_step "安装基础工具..."
    
    yum install -y net-tools vim wget curl git bash-completion
    
    log_info "基础工具安装完成"
}

# 安装OpenStack客户端
install_openstack_client() {
    log_step "安装OpenStack客户端..."
    
    yum install -y centos-release-openstack-train
    yum install -y python-openstackclient openstack-selinux
    
    log_info "OpenStack客户端安装完成"
}

# ==================== 第二步：依赖服务安装（仅控制节点） ====================

# 安装MariaDB
install_mariadb() {
    log_step "安装MariaDB数据库..."
    
    yum install -y mariadb mariadb-server python2-PyMySQL
    
    cat > /etc/my.cnf.d/openstack.cnf <<EOF
[mysqld]
bind-address = $CONTROLLER_IP
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # 安全配置（自动应答）
    mysql_secure_installation <<EOF

y
$DB_PASSWORD
$DB_PASSWORD
y
y
y
y
EOF
    
    log_info "MariaDB安装完成"
}

# 创建数据库
create_databases() {
    log_step "创建OpenStack数据库..."
    
    mysql -u root -p$DB_PASSWORD <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$DB_PASSWORD';

CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$DB_PASSWORD';

CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$DB_PASSWORD';

CREATE DATABASE nova_api;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$DB_PASSWORD';

CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$DB_PASSWORD';

CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$DB_PASSWORD';

CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$DB_PASSWORD';

FLUSH PRIVILEGES;
EOF
    
    log_info "数据库创建完成"
}

# 安装RabbitMQ
install_rabbitmq() {
    log_step "安装RabbitMQ消息队列..."
    
    yum install -y rabbitmq-server
    
    systemctl enable rabbitmq-server
    systemctl start rabbitmq-server
    
    rabbitmqctl add_user openstack $RABBIT_PASSWORD
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"
    
    log_info "RabbitMQ安装完成"
}

# 安装Memcached
install_memcached() {
    log_step "安装Memcached缓存服务..."
    
    yum install -y memcached python-memcached
    
    sed -i "s/OPTIONS=.*/OPTIONS=\"-l $CONTROLLER_IP,127.0.0.1\"/" /etc/sysconfig/memcached
    
    systemctl enable memcached
    systemctl start memcached
    
    log_info "Memcached安装完成"
}

# 安装Etcd
install_etcd() {
    log_step "安装Etcd键值存储..."
    
    yum install -y etcd
    
    cat > /etc/etcd/etcd.conf <<EOF
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://$CONTROLLER_IP:2380"
ETCD_LISTEN_CLIENT_URLS="http://$CONTROLLER_IP:2379"
ETCD_NAME="controller"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$CONTROLLER_IP:2380"
ETCD_INITIAL_CLUSTER="controller=http://$CONTROLLER_IP:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_ADVERTISE_CLIENT_URLS="http://$CONTROLLER_IP:2379"
EOF
    
    systemctl enable etcd
    systemctl start etcd
    
    log_info "Etcd安装完成"
}

# ==================== 第三步：安装Keystone（仅控制节点） ====================

install_keystone() {
    log_step "安装Keystone身份认证服务..."
    
    yum install -y openstack-keystone httpd mod_wsgi
    
    cat > /etc/keystone/keystone.conf <<EOF
[DEFAULT]
[database]
connection = mysql+pymysql://keystone:$DB_PASSWORD@$CONTROLLER_IP/keystone

[token]
provider = fernet
EOF
    
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    
    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    
    keystone-manage bootstrap --bootstrap-password $ADMIN_PASSWORD \
        --bootstrap-admin-url http://$CONTROLLER_IP:5000/v3/ \
        --bootstrap-internal-url http://$CONTROLLER_IP:5000/v3/ \
        --bootstrap-public-url http://$CONTROLLER_IP:5000/v3/ \
        --bootstrap-region-id RegionOne
    
    echo "ServerName $CONTROLLER_HOST" >> /etc/httpd/conf/httpd.conf
    ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
    
    systemctl enable httpd
    systemctl start httpd
    
    # 创建环境变量文件
    cat > /root/admin-openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_AUTH_URL=http://$CONTROLLER_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
    
    source /root/admin-openrc
    
    # 创建service项目和demo项目
    openstack project create --domain default --description "Service Project" service
    openstack project create --domain default --description "Demo Project" demo
    openstack user create --domain default --password $ADMIN_PASSWORD demo
    openstack role create user
    openstack role add --project demo --user demo user
    
    log_info "Keystone安装完成"
}

# ==================== 第四步：安装Glance（仅控制节点） ====================

install_glance() {
    log_step "安装Glance镜像服务..."
    
    # 创建服务凭证
    openstack user create --domain default --password $GLANCE_PASSWORD glance
    openstack role add --project service --user glance admin
    openstack service create --name glance --description "OpenStack Image" image
    openstack endpoint create --region RegionOne image public http://$CONTROLLER_IP:9292
    openstack endpoint create --region RegionOne image internal http://$CONTROLLER_IP:9292
    openstack endpoint create --region RegionOne image admin http://$CONTROLLER_IP:9292
    
    yum install -y openstack-glance
    
    cat > /etc/glance/glance-api.conf <<EOF
[DEFAULT]
[database]
connection = mysql+pymysql://glance:$DB_PASSWORD@$CONTROLLER_IP/glance

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $GLANCE_PASSWORD

[paste_deploy]
flavor = keystone
EOF
    
    su -s /bin/sh -c "glance-manage db_sync" glance
    
    systemctl enable openstack-glance-api.service
    systemctl start openstack-glance-api.service
    
    # 下载并上传测试镜像
    wget -q http://download.cirros-cloud.net/0.5.2/cirros-0.5.2-x86_64-disk.img
    openstack image create "cirros" \
        --file cirros-0.5.2-x86_64-disk.img \
        --disk-format qcow2 \
        --container-format bare \
        --public
    
    log_info "Glance安装完成"
}

# ==================== 第五步：安装Nova ====================

install_nova_controller() {
    log_step "安装Nova计算服务（控制节点）..."
    
    # 创建服务凭证
    openstack user create --domain default --password $NOVA_PASSWORD nova
    openstack role add --project service --user nova admin
    openstack service create --name nova --description "OpenStack Compute" compute
    openstack endpoint create --region RegionOne compute public http://$CONTROLLER_IP:8774/v2.1
    openstack endpoint create --region RegionOne compute internal http://$CONTROLLER_IP:8774/v2.1
    openstack endpoint create --region RegionOne compute admin http://$CONTROLLER_IP:8774/v2.1
    
    openstack user create --domain default --password $PLACEMENT_PASSWORD placement
    openstack role add --project service --user placement admin
    openstack service create --name placement --description "Placement API" placement
    openstack endpoint create --region RegionOne placement public http://$CONTROLLER_IP:8778
    openstack endpoint create --region RegionOne placement internal http://$CONTROLLER_IP:8778
    openstack endpoint create --region RegionOne placement admin http://$CONTROLLER_IP:8778
    
    yum install -y openstack-nova-api openstack-nova-conductor \
        openstack-nova-console openstack-nova-novncproxy \
        openstack-nova-scheduler openstack-nova-placement-api
    
    cat > /etc/nova/nova.conf <<EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:$RABBIT_PASSWORD@$CONTROLLER_IP
my_ip = $CONTROLLER_IP

[api]
auth_strategy = keystone

[api_database]
connection = mysql+pymysql://nova:$DB_PASSWORD@$CONTROLLER_IP/nova_api

[database]
connection = mysql+pymysql://nova:$DB_PASSWORD@$CONTROLLER_IP/nova

[glance]
api_servers = http://$CONTROLLER_IP:9292

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = $NOVA_PASSWORD

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://$CONTROLLER_IP:5000/v3
username = placement
password = $PLACEMENT_PASSWORD

[vnc]
enabled = true
server_listen = \$my_ip
server_proxyclient_address = \$my_ip
EOF
    
    su -s /bin/sh -c "nova-manage api_db sync" nova
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
    su -s /bin/sh -c "nova-manage db sync" nova
    
    systemctl enable openstack-nova-api.service \
        openstack-nova-consoleauth.service \
        openstack-nova-scheduler.service \
        openstack-nova-conductor.service \
        openstack-nova-novncproxy.service
    
    systemctl start openstack-nova-api.service \
        openstack-nova-consoleauth.service \
        openstack-nova-scheduler.service \
        openstack-nova-conductor.service \
        openstack-nova-novncproxy.service
    
    log_info "Nova控制节点安装完成"
}

install_nova_compute() {
    log_step "安装Nova计算服务（计算节点）..."
    
    yum install -y openstack-nova-compute
    
    cat > /etc/nova/nova.conf <<EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:$RABBIT_PASSWORD@$CONTROLLER_IP
my_ip = $COMPUTE_IP

[api]
auth_strategy = keystone

[glance]
api_servers = http://$CONTROLLER_IP:9292

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = $NOVA_PASSWORD

[libvirt]
virt_type = qemu

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://$CONTROLLER_IP:5000/v3
username = placement
password = $PLACEMENT_PASSWORD

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = \$my_ip
novncproxy_base_url = http://$CONTROLLER_IP:6080/vnc_auto.html
EOF
    
    systemctl enable libvirtd.service openstack-nova-compute.service
    systemctl start libvirtd.service openstack-nova-compute.service
    
    log_info "Nova计算节点安装完成"
}

# ==================== 第六步：安装Neutron ====================

install_neutron_controller() {
    log_step "安装Neutron网络服务（控制节点）..."
    
    # 创建服务凭证
    openstack user create --domain default --password $NEUTRON_PASSWORD neutron
    openstack role add --project service --user neutron admin
    openstack service create --name neutron --description "OpenStack Networking" network
    openstack endpoint create --region RegionOne network public http://$CONTROLLER_IP:9696
    openstack endpoint create --region RegionOne network internal http://$CONTROLLER_IP:9696
    openstack endpoint create --region RegionOne network admin http://$CONTROLLER_IP:9696
    
    yum install -y openstack-neutron openstack-neutron-ml2 \
        openstack-neutron-linuxbridge ebtables
    
    cat > /etc/neutron/neutron.conf <<EOF
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:$RABBIT_PASSWORD@$CONTROLLER_IP
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[database]
connection = mysql+pymysql://neutron:$DB_PASSWORD@$CONTROLLER_IP/neutron

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASSWORD

[nova]
auth_url = http://$CONTROLLER_IP:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_PASSWORD

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF
    
    cat > /etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vxlan]
vni_ranges = 1:1000

[securitygroup]
enable_ipset = true
EOF
    
    cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini <<EOF
[linux_bridge]
physical_interface_mappings = provider:ens33

[vxlan]
enable_vxlan = true
local_ip = $CONTROLLER_IP
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOF
    
    cat > /etc/neutron/l3_agent.ini <<EOF
[DEFAULT]
interface_driver = linuxbridge
EOF
    
    cat > /etc/neutron/dhcp_agent.ini <<EOF
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
EOF
    
    cat > /etc/neutron/metadata_agent.ini <<EOF
[DEFAULT]
nova_metadata_host = $CONTROLLER_IP
metadata_proxy_shared_secret = METADATA_SECRET
EOF
    
    cat >> /etc/nova/nova.conf <<EOF

[neutron]
auth_url = http://$CONTROLLER_IP:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASSWORD
EOF
    
    ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
    
    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
        --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
    
    systemctl restart openstack-nova-api.service
    
    systemctl enable neutron-server.service \
        neutron-linuxbridge-agent.service \
        neutron-dhcp-agent.service \
        neutron-metadata-agent.service \
        neutron-l3-agent.service
    
    systemctl start neutron-server.service \
        neutron-linuxbridge-agent.service \
        neutron-dhcp-agent.service \
        neutron-metadata-agent.service \
        neutron-l3-agent.service
    
    log_info "Neutron控制节点安装完成"
}

install_neutron_compute() {
    log_step "安装Neutron网络服务（计算节点）..."
    
    yum install -y openstack-neutron-linuxbridge ebtables ipset
    
    cat > /etc/neutron/neutron.conf <<EOF
[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASSWORD@$CONTROLLER_IP
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASSWORD

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF
    
    cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini <<EOF
[linux_bridge]
physical_interface_mappings = provider:ens33

[vxlan]
enable_vxlan = true
local_ip = $COMPUTE_IP
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOF
    
    cat >> /etc/nova/nova.conf <<EOF

[neutron]
auth_url = http://$CONTROLLER_IP:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASSWORD
EOF
    
    systemctl restart openstack-nova-compute.service
    systemctl enable neutron-linuxbridge-agent.service
    systemctl start neutron-linuxbridge-agent.service
    
    log_info "Neutron计算节点安装完成"
}

# ==================== 第七步：安装Cinder（仅控制节点） ====================

install_cinder() {
    log_step "安装Cinder块存储服务..."
    
    # 创建服务凭证
    openstack user create --domain default --password $CINDER_PASSWORD cinder
    openstack role add --project service --user cinder admin
    openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
    openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
    
    openstack endpoint create --region RegionOne volumev2 public http://$CONTROLLER_IP:8776/v2/%\(project_id\)s
    openstack endpoint create --region RegionOne volumev2 internal http://$CONTROLLER_IP:8776/v2/%\(project_id\)s
    openstack endpoint create --region RegionOne volumev2 admin http://$CONTROLLER_IP:8776/v2/%\(project_id\)s
    
    openstack endpoint create --region RegionOne volumev3 public http://$CONTROLLER_IP:8776/v3/%\(project_id\)s
    openstack endpoint create --region RegionOne volumev3 internal http://$CONTROLLER_IP:8776/v3/%\(project_id\)s
    openstack endpoint create --region RegionOne volumev3 admin http://$CONTROLLER_IP:8776/v3/%\(project_id\)s
    
    yum install -y openstack-cinder
    
    cat > /etc/cinder/cinder.conf <<EOF
[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASSWORD@$CONTROLLER_IP
auth_strategy = keystone
my_ip = $CONTROLLER_IP

[database]
connection = mysql+pymysql://cinder:$DB_PASSWORD@$CONTROLLER_IP/cinder

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = $CINDER_PASSWORD

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF
    
    su -s /bin/sh -c "cinder-manage db sync" cinder
    
    cat >> /etc/nova/nova.conf <<EOF

[cinder]
os_region_name = RegionOne
EOF
    
    systemctl restart openstack-nova-api.service
    
    systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
    systemctl start openstack-cinder-api.service openstack-cinder-scheduler.service
    
    log_info "Cinder安装完成"
}

# ==================== 验证部署 ====================

verify_deployment() {
    log_step "验证部署结果..."
    
    source /root/admin-openrc
    
    echo ""
    log_info "========== 服务状态 =========="
    echo ""
    
    log_info "1. Keystone服务:"
    openstack token issue > /dev/null 2>&1 && log_info "   ✓ 正常" || log_error "   ✗ 异常"
    
    log_info "2. Glance服务:"
    openstack image list > /dev/null 2>&1 && log_info "   ✓ 正常" || log_error "   ✗ 异常"
    
    log_info "3. Nova服务:"
    openstack compute service list > /dev/null 2>&1 && log_info "   ✓ 正常" || log_error "   ✗ 异常"
    
    log_info "4. Neutron服务:"
    openstack network agent list > /dev/null 2>&1 && log_info "   ✓ 正常" || log_error "   ✗ 异常"
    
    log_info "5. Cinder服务:"
    openstack volume service list > /dev/null 2>&1 && log_info "   ✓ 正常" || log_error "   ✗ 异常"
    
    echo ""
}

# ==================== 主函数 ====================

main() {
    check_root
    select_node_type
    
    echo ""
    read -p "是否开始部署？(y/n): " confirm
    if [ "$confirm" != "y" ]; then
        log_info "部署已取消"
        exit 0
    fi
    
    # 第一步：基础环境配置
    log_step "========== 第一步：基础环境配置 =========="
    configure_hostname
    configure_hosts
    configure_yum
    disable_security
    configure_ntp
    install_basic_tools
    install_openstack_client
    
    log_info "基础环境配置完成，建议重启系统后继续"
    read -p "是否立即重启？重启后请重新运行脚本继续部署 (y/n): " reboot_confirm
    if [ "$reboot_confirm" == "y" ]; then
        reboot
    fi
    
    # 根据节点类型执行不同部署
    if [ "$NODE_TYPE" == "controller" ]; then
        # 第二步：依赖服务
        log_step "========== 第二步：依赖服务安装 =========="
        install_mariadb
        create_databases
        install_rabbitmq
        install_memcached
        install_etcd
        
        # 第三步到第七步：核心组件
        log_step "========== 第三步：Keystone安装 =========="
        install_keystone
        
        log_step "========== 第四步：Glance安装 =========="
        install_glance
        
        log_step "========== 第五步：Nova控制节点安装 =========="
        install_nova_controller
        
        log_step "========== 第六步：Neutron控制节点安装 =========="
        install_neutron_controller
        
        log_step "========== 第七步：Cinder安装 =========="
        install_cinder
        
    else
        # 计算节点只需要安装Nova和Neutron
        log_step "========== 计算节点部署 =========="
        install_nova_compute
        install_neutron_compute
    fi
    
    # 验证部署
    if [ "$NODE_TYPE" == "controller" ]; then
        verify_deployment
    fi
    
    echo ""
    log_info "=========================================="
    log_info "部署完成！"
    if [ "$NODE_TYPE" == "controller" ]; then
        log_info "Horizon Dashboard: http://$CONTROLLER_IP/dashboard"
        log_info "用户名: admin"
        log_info "密码: $ADMIN_PASSWORD"
        log_info "环境变量文件: /root/admin-openrc"
    fi
    log_info "=========================================="
    echo ""
}

# 执行主函数
main
