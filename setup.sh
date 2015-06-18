#!/bin/bash
#Sets up Nginx, Microcache, PageSpeed Module, MariaDB 10, HHVM w/ PHP-FPM as fallback on Ubuntu (14.04x64)
#CONFIGURATION
echo "Domain or IP: "
read SERVERNAMEORIP
echo "Database Name: "
read MYSQLDATABASE
echo "Database Password: "
read MYSQLPASS
echo "Please enter NGX Pagespeed version number which you can get from "
echo "https://github.com/pagespeed/ngx_pagespeed/releases "
echo "Example: 1.9.32.3 "
echo "NGX Version: "
read NPS_VERSION
echo "Is the above information correct? Yes to install, no to exit."
select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done
#update everything
sudo add-apt-repository -s -y ppa:nginx/stable
wget -O - http://dl.hhvm.com/conf/hhvm.gpg.key | sudo apt-key add -
echo deb http://dl.hhvm.com/ubuntu trusty main | sudo tee /etc/apt/sources.list.d/hhvm.list
apt-get update

#install tools
sudo apt-get install build-essential zlib1g-dev libpcre3 libpcre3-dev unzip git-core curl wget dpkg-dev -y

#remove apache
#sudo service apache2 stop
#sudo apt-get remove --purge apache2 apache2-utils apache2.2-bin apache2-common -y
#sudo apt-get autoremove -y
#sudo apt-get autoclean -y

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

#get nginx purge
cd $NGINX_BUILD_DIR/debian/modules
wget http://labs.frickle.com/files/ngx_cache_purge-2.3.tar.gz
tar -xzvf ngx_cache_purge-2.3.tar.gz

sed -i 's/^\(\s*\)\(--add-module=.*[^\]\)$/\1\2 \\\
\1--add-module=\$(MODULESDIR)\/ngx_cache_purge-2.3 \\\
\1--add-module=\$(MODULESDIR\)\/ngx_pagespeed-release-'${NPS_VERSION}'-beta/g' $NGINX_BUILD_DIR/debian/rules
#sed -i '/--add-module=\$(MODULESDIR)\/ngx_http_substitutions_filter_module/i--add-module=\$(MODULESDIR)\/ngx_pagespeed-release-|NPS_VERSION|-beta \\' $NGINX_BUILD_DIR/debian/rules
#sed -i '/--add-module=\$(MODULESDIR)\/nginx-cache-purge \\/i--add-module=\$(MODULESDIR)\/ngx_pagespeed-release-|NPS_VERSION|-beta \\' $NGINX_BUILD_DIR/debian/rules
#sed -i '/--add-module=\$(MODULESDIR)\/ngx_pagespeed-release-|NPS_VERSION|-beta \\/i--add-module=\$(MODULESDIR)\/nginx-cache-purge \\' $NGINX_BUILD_DIR/debian/rules
#sed -ie "s/|NPS_VERSION|/$NPS_VERSION/g" $NGINX_BUILD_DIR/debian/rules

#get openssl
#wget http://www.openssl.org/source/openssl-1.0.2c.tar.gz
#tar -xzvf openssl-1.0.2a.tar.gz

#build nginx
cd $NGINX_BUILD_DIR
dpkg-buildpackage -b
cd /opt/nginx/
sudo dpkg -i nginx_*_all.deb nginx-common_*_all.deb nginx-doc_*_all.deb nginx-full_*_amd64.deb

mkdir -p /var/cache/pagespeed/
chown www-data:www-data /var/cache/pagespeed/

#you may need to enter a password for mysql-server
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQLPASS}"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQLPASS}"

#remove mysql
#sudo service mysql stop
#sudo apt-get remove --purge mysql-server mysql-client mysql-common -y
#sudo apt-get autoremove -y
#sudo apt-get autoclean -y
#sudo rm -rf /var/lib/mysql/
#sudo rm -rf /etc/mysql/

#install mariadb
sudo apt-get -y install mariadb-server

#install php
apt-get install -y php5-mysql php5-fpm php5-gd php5-cli

#configure phpfpm settings
sed -i "s/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini
sed -i "s/^;listen.owner = www-data/listen.owner = www-data/" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.group = www-data/listen.group = www-data/" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.mode = 0660/listen.mode = 0660/" /etc/php5/fpm/pool.d/www.conf
sed -i "s/listen = \/var\/run\/php5-fpm.sock/listen = 127.0.0.1:8000/" /etc/php5/fpm/pool.d/www.conf
sudo service php5-fpm restart
#need to add fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name; to fastcgi_params

#install hhvm
sudo apt-get install -y hhvm
sudo /usr/share/hhvm/install_fastcgi.sh
sudo update-rc.d hhvm defaults
sudo service hhvm restart
sudo /usr/bin/update-alternatives --install /usr/bin/php php /usr/bin/hhvm 60

#configure nginx
#more advanced configuration options and plugin info available here: https://rtcamp.com/wordpress-nginx/tutorials/single-site/fastcgi-cache-with-purging/
mkdir /var/run/nginx-cache

sed -i "s/^\tworker_connections 768;/\tworker_connections 1536;/" /etc/nginx/nginx.conf

sed -i "s/^\tssl_prefer_server_ciphers on;/\tssl_prefer_server_ciphers on;\n\n\tfastcgi_cache_path \/var\/run\/nginx-cache\/fcgi levels=1:2 keys_zone=microcache:100m max_size=1024m inactive=1h;/" /etc/nginx/nginx.conf

cat << EOF > upstream
upstream php {
        # server unix:/run/php5-fpm.sock;
        server 127.0.0.1:9000;
        server 127.0.0.1:8000 backup;
}
EOF
echo -e '0r upstream\nw' | ed /etc/nginx/sites-available/default
sed -i "s/^\tindex index.html index.htm index.nginx-debian.html;/\tindex index.php index.html index.htm;/" /etc/nginx/sites-available/default
sed -i "s/^\tserver_name _;/\tserver_name $SERVERNAMEORIP;\n\n\n\t\tset \$no_cache 0;\n\t\tif (\$request_method = POST){set \$no_cache 1;}\n\t\tif (\$query_string != \"\"){set \$no_cache 1;}\n\t\tif (\$http_cookie = \"PHPSESSID\"){set \$no_cache 1;}\n\t\tif (\$request_uri ~* \"\/wp-admin\/|\/xmlrpc.php|wp-.*.php|\/feed\/|index.php|sitemap(_index)?.xml\") {set \$no_cache 1;}\n\t\tif (\$http_cookie ~* \"comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in\"){set \$no_cache 1;}\n/" /etc/nginx/sites-available/default
sed -i "s/^\tlocation \/ {/\n\tlocation ~ \\\.php$ {\n\t\ttry_files \$uri =404;\n\t\tfastcgi_split_path_info ^(.+\\\.php)(\/.+)\$;\n\t\tfastcgi_cache  microcache;\n\t\tfastcgi_cache_key \$scheme\$host\$request_uri\$request_method;\n\t\tfastcgi_cache_valid 200 301 302 30s;\n\t\tfastcgi_cache_use_stale updating error timeout invalid_header http_500;\n\t\tfastcgi_pass_header Set-Cookie;\n\t\tfastcgi_no_cache \$no_cache;\n\t\tfastcgi_cache_bypass \$no_cache;\n\t\tfastcgi_pass_header Cookie;\n\t\tfastcgi_ignore_headers Cache-Control Expires Set-Cookie;\n\t\tfastcgi_pass php;\n\t\tfastcgi_index index.php;\n\t\tinclude fastcgi_params;\n\t}\n\tlocation \/ {/" /etc/nginx/sites-available/default

#just restarting to make sure they have latest
service nginx restart
service mysql restart
service php5-fpm restart
service hhvm restart

##create MySql Database
mysql -uroot -p$MYSQLPASS -e "create database ${MYSQLDATABASE}"

mkdir /var/www/$SERVERNAMEORIP
cd /var/www/$SERVERNAMEORIP
#get WordPress latest
wget http://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz
#move WordPress to web woot
mv /var/www/$SERVERNAMEORIP/wordpress/* /var/www/$SERVERNAMEORIP/
chown -R www-data:www-data /var/www/$SERVERNAMEORIP/

#cleanup folder
rm -rf wordpress

#Done!
#Go through WordPress install with database and password you setup here
#You may need to create wp-config.php
