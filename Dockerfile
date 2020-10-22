FROM gitlab-url:5000/containers/internal/ubi7:7.8 as builder

MAINTAINER jonesry

# Move local repos over to base
COPY repos/*.repo /etc/yum.repos.d/

# All Packages needed to build both Suricata and Zeek
RUN yum -y --setopt=tsflags=nodocs update  && yum -y --setopt=tsflags=nodocs install \
jq openssl-devel PyYAML lz4-devel gcc libpcap-devel pcre-devel libyaml-devel file-devel zlib-devel jansson-devel nss-devel libcap-ng-devel libnet-devel tar make libnetfilter_queue-devel lua-devel cmake make gcc-c++ flex bison python-devel swig rustc cargo llvm7.0 wget git


####>>>>>>>>>>>>>>>> Suricata Install <<<<<<<<<<<<<<<<<<<####
WORKDIR /src
ENV VERSION 5.0.3
COPY suricata-${VERSION}.tar.gz .
RUN  tar xzf suricata-${VERSION}.tar.gz

WORKDIR /src/suricata-${VERSION}

RUN ./configure --libdir=/usr/lib64 --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-nfqueue --enable-lua --disable-gccmarch-native
RUN make
RUN make install install-conf DESTDIR=/fakeroot




####>>>>>>>>>>>>>>>> Zeek Install <<<<<<<<<<<<<<<<<<<<<< ###
WORKDIR /src
ENV VERSION 3.0.3
COPY zeek-${VERSION}.tar.gz .
RUN tar xzvf zeek-${VERSION}.tar.gz

WORKDIR /src/zeek-${VERSION}

RUN ./configure 
RUN make 
RUN make install 




############################## STAGE 2 ########################################################################


FROM gitlab-url:5000/containers/internal/ubi7:7.8 as runner

# Move local repos over
COPY repos/*.repo /etc/yum.repos.d/


# Install packages, many just for testing purposes (will need to cleanup when done with testing)
RUN yum -y --setopt=tsflags=nodocs update  && yum -y --setopt=tsflags=nodocs install \
jq openssl-devel PyYAML lz4-devel gcc libpcap-devel pcre-devel libyaml-devel file-devel zlib-devel jansson-devel nss-devel libcap-ng-devel libnet-devel tar libnetfilter_queue-devel lua-devel flex bison python-devel swig rustc cargo llvm7.0 wget git \
        file \
        findutils \
        hiredis \
        hyperscan \
        iproute \
        jansson \
        lua-libs \
        libyaml \
        libnfnetlink \
        libnetfilter_queue \
        libnet \
        libcap-ng \
        libevent \
        libmaxminddb \
        libpcap \
        libprelude \
        logrotate \
        lsof    \
        lz4 \
        net-tools \
        nss \
        nss-softokn \
        openssh-server \
        passwd \
        pcre \
        procps-ng \
        python2 \
        python3-yaml \
        sudo \
        tcpdump \
        tcpreplay \
        wget \
        which \
        zlib \
        && yum clean all 



# update trust for proxies
COPY certs/*.crt /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust


# Copy over Suricata and Zeek files from Builder image
COPY --from=builder /fakeroot /
COPY --from=builder /usr/local/zeek /usr/local/zeek

# Do not need to build here
# RUN /usr/local/zeek/bin/zeekctl deploy




###################################### OWL H PORTION #################################################################
# OwlH Suricata
RUN mkdir -p /etc/suricata/rules && \
        cd /etc/suricata/rules && \
        cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.old
COPY owlh/suricata.yaml /etc/suricata/suricata.yaml

# OwlH Zeek
COPY owlh/owlh.zeek /usr/local/zeek/share/zeek/site/

# Expose OwlH Node
EXPOSE 50002
RUN mkdir /tmp/owlhinstaller && \
        cd /tmp/owlhinstaller && \
        wget http://localrepo.org/misc-utils/owlhinstaller.tar.gz && \
        tar -xzf owlhinstaller.tar.gz && \
        chmod +x /tmp/owlhinstaller/owlhinstaller

COPY owlh/config.json /tmp/owlhinstaller/
COPY services/owlhnode.service /etc/systemd/system/
RUN chmod 644 /tmp/owlhinstaller/config.json && \
        ls -l /tmp/owlhinstaller/ && \
        cd /tmp/owlhinstaller/ && \
        ./owlhinstaller && sleep 10


####################################### SYSTEMD Related ##############################################################
RUN yum install -y systemd
STOPSIGNAL SIGRTMIN+3
# RUN setsebool -P container_manage_cgroup true && \   # run on host OS if selinux present (needs testing)
RUN systemctl mask sys-fs-fuse-connections.mount && \
systemctl enable owlhnode.service
# Start systemd
CMD ["/usr/sbin/init"]
