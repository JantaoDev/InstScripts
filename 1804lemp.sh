#!/bin/bash
set -e
echo '----------------------------------'
echo ' Install scripts for Ubuntu 18.04 '
echo '----------------------------------'
echo '1) Update & upgrade system'
echo '2) Enable UFW firewall'
echo '3) Install LEMP'
echo '4) Create dedicated user for web-server'
echo '5) Create Symfony site'
echo '0) Quit'
echo 
read -p 'What you want? ' opt
# options=("Update & upgrade system" "Enable UFW firewall" "Install LEMP" "Quit")
# select opt in "${options[@]}"
case $opt in
    1)
        apt-get update
        apt-get -y upgrade
        echo '----------------------------------'
        echo ' Done'
        echo '----------------------------------'
        ;;
    2)
        apt-get -y install ufw
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow OpenSSH
        ufw enable
        echo '----------------------------------'
        echo ' Done'
        echo '----------------------------------'
        ;;
    3)
        # Install LEMP
        apt-get -y install nginx
        ufw allow "Nginx Full"
        apt-get -y install mysql-server
        mysql_secure_installation
        apt-get -y install php-fpm php-mysql
        apt-get -y install php-gd php-curl php-pear php-mbstring
        # Change configuration
        read -p "Enter POST size (example 8M): " postsize
        read -p "Enter timezone (example Europe\/Minsk): " timezone
        # Change PHP configuration file
        sed -r -i "s/;?cgi.fix_pathinfo\s*=\s*[0-9]+/cgi.fix_pathinfo=0/" /etc/php/7.2/fpm/php.ini
        sed -r -i "s/;?post_max_size\s*=\s*\S+/post_max_size=$postsize/" /etc/php/7.2/fpm/php.ini
        sed -r -i "s/;?upload_max_filesize\s*=\s*\S+/upload_max_filesize=$postsize/" /etc/php/7.2/fpm/php.ini
        sed -r -i "s/;?date.timezone\s*=\s*\S*/date.timezone=$timezone/" /etc/php/7.2/fpm/php.ini
        sed -r -i "s/;?expose_php\s*=\s*\S+/expose_php=Off/" /etc/php/7.2/fpm/php.ini
        # Change nginx configuration file
        sed -r -i "s/.*server_tokens.*//" /etc/nginx/nginx.conf
        sed -r -i "s/.*client_max_body_size.*//" /etc/nginx/nginx.conf
        sed -r -i "s/http\s*\{/http {\n        client_max_body_size $postsize;\n        server_tokens off;\n/" /etc/nginx/nginx.conf
        # Change MySql configuration file
        sed -r -i "s/\[mysqld\]/[mysqld]\nsql_mode = \"STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION\"\n/" /etc/mysql/mysql.conf.d/mysqld.cnf
        # Change folder permissions
        chmod 777 /var/lib/php
        chmod 777 /var/lib/nginx
        # Restart
        /etc/init.d/mysql restart
        /etc/init.d/php7.2-fpm restart
        /etc/init.d/nginx restart

        echo '----------------------------------'
        echo ' Done'
        echo '----------------------------------'
        ;;
    4)
        read -p "Enter user name: " webuser
        adduser $webuser
        usermod -g www-data $webuser
        sed -r -i "s/^user\s+.*;/user $webuser www-data;/" /etc/nginx/nginx.conf
        sed -r -i "s/user\s*=\s*\S*/user = $webuser/" /etc/php/7.2/fpm/pool.d/www.conf
        sed -r -i "s/listen\.owner\s*=\s*\S*/listen.owner = $webuser/" /etc/php/7.2/fpm/pool.d/www.conf
        rm /var/log/nginx/*
        chown -R $webuser:www-data /var/www
        /etc/init.d/php7.2-fpm restart
        /etc/init.d/nginx restart
        # Copy SSH key from root to user
        read -p "Are you want to copy SSH key from root to $webuser?" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            mkdir /home/$webuser/.ssh
            cp ~/.ssh/authorized_keys /home/$webuser/.ssh/authorized_keys
            chmod 600 /home/$webuser/.ssh/authorized_keys
            chmod 700 /home/$webuser/.ssh
            chown -R $webuser:www-data /home/$webuser/.ssh
        fi
        echo '----------------------------------'
        echo ' Done'
        echo '----------------------------------'
        ;;
    5)
        read -p "Enter site name: " sitename
        read -p "Enter web-user name: " webuser
        sitepassword=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        # Create database
        echo "CREATE DATABASE $sitename CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" | mysql -u root
        echo "GRANT ALL PRIVILEGES ON $sitename.* TO $sitename@localhost IDENTIFIED BY \"$sitepassword\";" | mysql -u root
        echo "FLUSH PRIVILEGES;" | mysql -u root
        # Create files
        mkdir /var/www/$sitename
        mkdir /var/www/$sitename/public
        echo "DATABASE_URL=mysql://$sitename:$sitepassword@127.0.0.1:3306/$sitename" > /var/www/$sitename/.env.local
        chown -R $webuser:www-data /var/www/$sitename
        # Add nginx configuration
        echo "server {" > /etc/nginx/sites-available/$sitename
        read -p "Are you want to set site as default" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            echo "        listen 80 default_server;" >> /etc/nginx/sites-available/$sitename
            echo "        listen [::]:80 default_server;" >> /etc/nginx/sites-available/$sitename
            rm /etc/nginx/sites-enabled/default
        else
            echo "        listen 80;" >> /etc/nginx/sites-available/$sitename
            echo "        listen [::]:80;" >> /etc/nginx/sites-available/$sitename
            read -p "Enter site domain (example.com): " sitedomain
            echo "        server_name $sitedomain www.$sitedomain;" >> /etc/nginx/sites-available/$sitename
        fi
        echo "        root /var/www/$sitename/public;" >> /etc/nginx/sites-available/$sitename
        echo "        location / {" >> /etc/nginx/sites-available/$sitename
        echo "                try_files \$uri /index.php\$is_args\$args;" >> /etc/nginx/sites-available/$sitename
        echo "        }" >> /etc/nginx/sites-available/$sitename
        echo "        location ~ ^/index\.php(/|$) {" >> /etc/nginx/sites-available/$sitename
        echo "                fastcgi_pass unix:/var/run/php/php7.2-fpm.sock;" >> /etc/nginx/sites-available/$sitename
        echo "                fastcgi_split_path_info ^(.+\.php)(/.*)$;" >> /etc/nginx/sites-available/$sitename
        echo "                include fastcgi_params;" >> /etc/nginx/sites-available/$sitename
        echo "                fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;" >> /etc/nginx/sites-available/$sitename
        echo "                fastcgi_param DOCUMENT_ROOT \$realpath_root;" >> /etc/nginx/sites-available/$sitename
        echo "                internal;" >> /etc/nginx/sites-available/$sitename
        echo "        }" >> /etc/nginx/sites-available/$sitename
        echo "        location ~ \.php$ {" >> /etc/nginx/sites-available/$sitename
        echo "                return 404;" >> /etc/nginx/sites-available/$sitename
        echo "        }" >> /etc/nginx/sites-available/$sitename
        echo "}" >> /etc/nginx/sites-available/$sitename
        ln -s /etc/nginx/sites-available/$sitename /etc/nginx/sites-enabled/$sitename
        # Restart nginx
        /etc/init.d/nginx restart
        echo '----------------------------------'
        echo ' Done'
        echo '----------------------------------'
        ;;
    0)
        ;;
    *) 
        echo "Invalid option"
        ;;
esac
