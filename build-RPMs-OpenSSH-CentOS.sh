#!/bin/bash
# Build OpenSSH RPM for CentOS 6|7|8
# Build by zt
# Tested ok on CentOS 6|7|8 with openssh version {7.5p1 to 8.3p1}
# ========
# Changelog Begin
# 20190403 Write all code for new
# 20191015 Fix bug that root could not login after upgrade on CentOS 7.x
# 20191016 Support CentOS 8
# 20200310 Support OpenSSH 8.2p1
# 20200531 Support OpenSSH 8.3p1
# 20200612 Optimize code
# Changelog End
# ========

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root"
    exit 1
fi

echo "Version: v6 20200618"

rhel_version=$(rpm -q --queryformat '%{VERSION}' centos-release)

if [ ! -x $1 ]; then
    version=$1
else    ``
    echo "Usage: sh $0 {openssh-version}(default is 8.3p1)"
    echo "version not provided '8.3p1' will be used."
    while true; do
        read -p "Do you want to continue [y/N]: " yn
        case $yn in
        [Yy]*)
            version="8.3p1"
            break
            ;;
        [Nn]*) exit ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
fi

function build_RPMs() {
    yum install -y pam-devel rpm-build rpmdevtools zlib-devel krb5-devel gcc wget perl libXt-devel imake gtk2-devel openssl-devel
    mkdir -p ~/rpmbuild/SOURCES && cd ~/rpmbuild/SOURCES
    wget -c https://mirrors.tuna.tsinghua.edu.cn/OpenBSD/OpenSSH/portable/openssh-${version}.tar.gz
    wget -c https://mirrors.tuna.tsinghua.edu.cn/OpenBSD/OpenSSH/portable/openssh-${version}.tar.gz.asc
    wget -c https://mirrors.tuna.tsinghua.edu.cn/slackware/slackware64-current/source/xap/x11-ssh-askpass/x11-ssh-askpass-1.2.4.1.tar.gz
    # # verify the file

    # update the pam sshd from the one included on the system
    # the default provided doesn't work properly on CentOS 6.5
    tar zxvf openssh-${version}.tar.gz
    yes | cp /etc/pam.d/sshd openssh-${version}/contrib/redhat/sshd.pam
    mv openssh-${version}.tar.gz{,.orig}
    tar zcpf openssh-${version}.tar.gz openssh-${version}
    cd
    tar zxvf ~/rpmbuild/SOURCES/openssh-${version}.tar.gz openssh-${version}/contrib/redhat/openssh.spec
    # edit the specfile
    cd openssh-${version}/contrib/redhat/
    chown root.root openssh.spec
    sed -i -e "s/%define no_gnome_askpass 0/%define no_gnome_askpass 1/g" openssh.spec
    sed -i -e "s/%define no_x11_askpass 0/%define no_x11_askpass 1/g" openssh.spec
    sed -i -e "s/BuildPreReq/BuildRequires/g" openssh.spec
    #if encounter build error with the follow line, comment it.
    sed -i -e "s/PreReq: initscripts >= 5.00/#PreReq: initscripts >= 5.00/g" openssh.spec
    #CentOS 7
    if [ "${rhel_version}" == "7" ]; then
        sed -i -e "s/BuildRequires: openssl-devel < 1.1/#BuildRequires: openssl-devel < 1.1/g" openssh.spec
    elif [ "${rhel_version}" == "8.0" ]; then
        sed -i -e "s/BuildRequires: openssl-devel < 1.1/#BuildRequires: openssl-devel < 1.1/g" openssh.spec
    fi
    if [ "${version}" == "8.2p1" ] || [ "${version}" == "8.3p1" ]; then
        sed -i "/%attr(0755,root,root) %{_libexecdir}\/openssh\/ssh-pkcs11-helper/ a\\%attr(0755,root,root) %{_libexecdir}\/openssh\/ssh-sk-helper" openssh.spec
        sed -i "/%attr(0644,root,root) %{_mandir}\/man8\/ssh-pkcs11-helper.8*/ a\\%attr(0644,root,root) %{_mandir}\/man8\/ssh-sk-helper.8*" openssh.spec
    fi
    rpmbuild -ba openssh.spec
    cd /root/rpmbuild/RPMS/x86_64/
    tar zcvf openssh-${version}-RPMs.el${rhel_version}.tar.gz openssh*
    mv openssh-${version}-RPMs.el${rhel_version}.tar.gz ~ && rm -rf ~/rpmbuild ~/openssh-${version}
    # openssh-${version}-RPMs.el${rhel_version}.tar.gz ready for use.

}

function upgrade_openssh() {
    cd /tmp
    mkdir openssh && cd openssh
    timestamp=$(date +%s)
    if [ ! -f ~/openssh-${version}-RPMs.el${rhel_version}.tar.gz ]; then
        echo "~/openssh-${version}-RPMs.el${rhel_version}.tar.gz not exist"
        exit 1
    fi
    cp ~/openssh-${version}-RPMs.el${rhel_version}.tar.gz ./
    tar zxf openssh-${version}-RPMs.el${rhel_version}.tar.gz
    cp /etc/pam.d/sshd pam-ssh-conf-${timestamp}
    rpm -Uvh *.rpm
    mv /etc/pam.d/sshd /etc/pam.d/sshd_${timestamp}
    yes | cp pam-ssh-conf-${timestamp} /etc/pam.d/sshd
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#UsePAM no/UsePAM yes/' /etc/ssh/sshd_config
    if [ $(rpm -q --queryformat '%{VERSION}' centos-release) == "7" ]; then
        chmod 600 /etc/ssh/ssh*
        systemctl restart sshd.service
    elif [ $(rpm -q --queryformat '%{VERSION}' centos-release) == "8.0" ]; then
        chmod 600 /etc/ssh/ssh*
        systemctl restart sshd.service
    else
        /etc/init.d/sshd restart
    fi
    cd
    rm -rf /tmp/openssh
    echo "New version upgrades as to lastest:" && $(ssh -V)
}

function main() {
    if [ -f ~/openssh-${version}-RPMs.el${rhel_version}.tar.gz ]; then
        echo "openssh-${version}-RPMs.el${rhel_version}.tar.gz file already exist, do you want to build again?"
        while true; do
            read -p "Continue build [y/N]: " yn
            case $yn in
            [Yy]*)
                build_RPMs
                break
                ;;
            [Nn]*) break ;;
            *) echo "Please answer yes or no." ;;
            esac
        done
    else
        echo "Start build openssh-${version}-RPMs ..."
        sleep 1s
        build_RPMs
    fi

    while true; do
        read -p "Do you want to install update now [y/N]: " yn
        case $yn in
        [Yy]*)
            upgrade_openssh
            break
            ;;
        [Nn]*) exit ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
}

main
