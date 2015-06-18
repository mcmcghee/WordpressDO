#!/bin/bash
#download nginx source
sudo apt-get -y build-dep nginx
sudo mkdir -p /opt/nginx
cd /opt/nginx
sudo apt-get source nginx

PSOL_VER=$(echo $NPS_VERSION | cut -d \- -f 1)
NGINX_VER=$(find ./nginx* -maxdepth 0 -type d | sed "s|^\./||")
NGINX_VER_NUM=$(echo $NGINX_VER | cut -d \- -f 2)
NGINX_BUILD_DIR=/opt/nginx/$NGINX_VER

#install pagespeed module
cd $NGINX_BUILD_DIR/debian/modules
wget https://github.com/pagespeed/ngx_pagespeed/archive/release-${NPS_VERSION}-beta.zip
unzip release-${NPS_VERSION}-beta.zip
cd ngx_pagespeed-release-${NPS_VERSION}-beta/
wget https://dl.google.com/dl/page-speed/psol/${NPS_VERSION}.tar.gz
tar -xzvf ${NPS_VERSION}.tar.gz  # extracts to psol/

sed -i 's/^\(\s*\)\(--add-module=.*[^\]\)$/\1\2 \\\
\1--add-module=\$(MODULESDIR\)\/ngx_pagespeed-release-'${NPS_VERSION}'-beta/g' $NGINX_BUILD_DIR/debian/rules
#sed -i '/--add-module=\$(MODULESDIR)\/ngx_http_substitutions_filter_module/i--add-module=\$(MODULESDIR)\/ngx_pagespeed-release-|NPS_VERSION|-beta \\' $NGINX_BUILD_DIR/debian/rules
#sed -i '/--add-module=\$(MODULESDIR)\/nginx-cache-purge \\/i--add-module=\$(MODULESDIR)\/ngx_pagespeed-release-|NPS_VERSION|-beta \\' $NGINX_BUILD_DIR/debian/rules
#sed -i '/--add-module=\$(MODULESDIR)\/ngx_pagespeed-release-|NPS_VERSION|-beta \\/i--add-module=\$(MODULESDIR)\/nginx-cache-purge \\' $NGINX_BUILD_DIR/debian/rules
#sed -ie "s/|NPS_VERSION|/$NPS_VERSION/g" $NGINX_BUILD_DIR/debian/rules

#get nginx purge
cd $NGINX_BUILD_DIR/debian/modules
wget http://labs.frickle.com/files/ngx_cache_purge-2.3.tar.gz
tar -xzvf ngx_cache_purge-2.3.tar.gz

#get openssl
#wget http://www.openssl.org/source/openssl-1.0.2c.tar.gz
#tar -xzvf openssl-1.0.2a.tar.gz

#build nginx
apt-get remove nginx
cd $NGINX_BUILD_DIR
dpkg-buildpackage -b
cd /opt/nginx/
sudo dpkg -i nginx_*_all.deb nginx-common_*_all.deb nginx-doc_*_all.deb nginx-full_*_amd64.deb
