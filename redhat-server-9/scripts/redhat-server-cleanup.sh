#!/bin/bash
# 
# Prepares a Red Hat Enterprise Linux 8 Server guest operating system.

export BUILD_USERNAME
export RHSM_USERNAME
export RHSM_PASSWORD

#### Register Red Hat Subscription Manager to enable updates. ###
echo '> Registering Red Hat Subscription Manager to enable updates ...'
subscription-manager register --username $RHSM_USERNAME --password $RHSM_PASSWORD --auto-attach

####  Only needed if installing the vmware guestinfo provider: https://github.com/vmware/cloud-init-vmware-guestinfo/blob/master/install.sh
#subscription-manager repos --enable rhel-server-rhscl-7-rpms
#yum -y install python27-python-pip

### Install additional packages. ### 
echo '> Installing additional packages ...'
sudo dnf install -y curl
sudo dnf install -y wget
sudo dnf install -y git
sudo dnf install -y net-tools
sudo dnf install -y unzip
sudo dnf install -y ca-certificates
sudo dnf install -y open-vm-tools

#https://kb.vmware.com/s/article/54986
echo "disable_vmware_customization: false" >> /etc/cloud/cloud.cfg
rm -rf /var/lib/cloud/seed/nocloud-net || true
if [ -f /etc/cloud/cloud.cfg.d/50-curtin-networking.cfg ]; then
    rm -rf /etc/cloud/cloud.cfg.d/50-curtin-networking.cfg || true
fi
rm -fr /var/lib/cloud/instances/
rm -fr /var/lib/cloud/instance 
rm -f /etc/machine-id /var/lib/dbus/machine-id
truncate -s 0 /etc/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

#### Update the guest operating system. ###
echo '> Updating the guest operating system ...'
sudo dnf update -y

### Clearing yum cache. ###
echo '> Clearing yum cache ...'
sudo dnf clean all

### Copy the Certificate Authority certificates and add to the certificate authority trust. ###
echo '> Copying the Certificate Authority certificates and adding to the certificate authority trust ...'
sudo chown -R root:root /tmp/root-ca.crt
sudo cat /tmp/root-ca.crt > /etc/pki/ca-trust/source/anchors/root-ca.crt
sudo chmod 644 /etc/pki/ca-trust/source/anchors/root-ca.crt
sudo update-ca-trust extract
sudo rm -rf /tmp/root-ca.crt

### Copy the SSH key to authorized_keys and set permissions. ###
echo '> Copying the SSH key to Authorized Keys and setting permissions ...'
sudo mkdir -p /home/$BUILD_USERNAME/.ssh
sudo chmod 700 /home/$BUILD_USERNAME/.ssh
sudo cat /tmp/id_ecdsa.pub > /home/$BUILD_USERNAME/.ssh/authorized_keys
sudo chmod 644 /home/$BUILD_USERNAME/.ssh/authorized_keys
sudo rm -rf /tmp/id_ecdsa.pub

### Configure SSH for Public Key Authentication. ###
echo '> Configuring SSH for Public Key Authentication ...'
sudo sed -i '/^PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config
sudo sed -i "s/.*PubkeyAuthentication.*/PubkeyAuthentication yes/g" /etc/ssh/sshd_config

### Restart the SSH daemon. ###
echo '> Restarting the SSH daemon. ...'
sudo systemctl restart sshd

# ### Disable SELinux. ### 
# echo '> Disabling SELinux ...'
# sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

### Disable and clean tmp. ### 
#echo '> Disabling and clean tmp ...'
#SOURCE_TEXT="v /tmp 1777 root root 10d"
#DEST_TEXT="#v /tmp 1777 root root 10d"
#sudo sed -i "s@${SOURCE_TEXT}@${DEST_TEXT}@g" /usr/lib/tmpfiles.d/tmp.conf
#sudo sed -i "s/\(^.*10d.*$\)/#\1/" /usr/lib/tmpfiles.d/tmp.conf

### Add After=dbus.service to VMware Tools daemon. ### 
echo '> Adding After=dbus.service to VMware Tools daemon ...'
sudo sed -i '/^After=vgauthd.service/a\After=dbus.service' /usr/lib/systemd/system/vmtoolsd.service

### Create a cleanup script. ###
echo '> Creating cleanup script ...'
sudo cat <<EOF > /tmp/clean.sh
#!/bin/bash

# Cleans all audit logs.
echo '> Cleaning all audit logs ...'
if [ -f /var/log/audit/audit.log ]; then
cat /dev/null > /var/log/audit/audit.log
fi
if [ -f /var/log/wtmp ]; then
cat /dev/null > /var/log/wtmp
fi
if [ -f /var/log/lastlog ]; then
cat /dev/null > /var/log/lastlog
fi

# Cleans persistent udev rules.
echo '> Cleaning persistent udev rules ...'
if [ -f /etc/udev/rules.d/70-persistent-net.rules ]; then
rm /etc/udev/rules.d/70-persistent-net.rules
fi

# Cleans /tmp directories.
echo '> Cleaning /tmp directories ...'
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /var/log/rhsm/*
rm -rf /var/cache/yum/*

# Cleans SSH keys.
echo '> Cleaning SSH keys ...'
#rm -f /etc/ssh/ssh_host_*

# Sets hostname to localhost.
echo '> Setting hostname to localhost ...'
cat /dev/null > /etc/hostname
hostnamectl set-hostname localhost

# Cleans yum.
echo '> Cleaning yum ...'
yum clean all

# Cleans the machine-id.
echo '> Cleaning the machine-id ...'
truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Cleans shell history.
echo '> Cleaning shell history ...'
unset HISTFILE
history -cw
echo > ~/.bash_history
rm -fr /root/.bash_history

# Run a sync for giggles. And then again.
sync && sync

EOF

### Change script permissions for execution. ### 
echo '> Changeing script permissions for execution ...'
sudo chmod +x /tmp/clean.sh

### Executes the cleauup script. ### 
echo '> Executing the cleanup script ...'
sudo /tmp/clean.sh

#### Unegister from Red Hat Subscription Manager. ###
echo '> Unegistering from Red Hat Subscription Manager ...'
subscription-manager unsubscribe --all
subscription-manager unregister
subscription-manager clean

# Reset any existing cloud-init state
#
cloud-init clean -s -l  || true

### All done. ### 
echo '> Done.'  


