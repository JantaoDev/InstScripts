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
echo '6) Install MTA'
echo '7) Install munin & monit'
echo '8) Disable root user and secure SSH'
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
        echo ' Done, please reboot the server'
        echo '----------------------------------'
        ;;
    2)
        apt-get -y install ufw
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow OpenSSH
        ufw enable
        echo '----------------------------------'
        echo ' Done, please logout and login'
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
        read -p "Enter timezone (example Europe\\\\/Minsk): " timezone
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
    6)
        echo "Select the configuration \"Internet Site\" during installation"
        echo "Then write the site domain"
        echo "(if the mail server is not on this server, it is better to write a subdomain, because it will add the domain to localhost and will not send e-mail to the mail server)"
        echo ""
        echo "Press any key..."
        read -n 1
        apt-get -y install postfix mailutils
        read -p "Enter root emails (comma-separated): " emails
        echo "postmaster: root" > /etc/aliases
        echo "root: $emails" >> /etc/aliases
        newaliases
        read -p "Are you want to send test e-mails to $emails?" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            echo "Test e-mail" | mail -s "Test message from my VPS" root
        fi
        echo '----------------------------------'
        echo ' Done'
        echo '----------------------------------'
        ;;
    7)
        apt-get -y install munin munin-node
        read -p "Enter server name (domain) for munin: " servname
        sed -r -i "s/\[localhost\.localdomain\]/[$servname]/" /etc/munin/munin.conf
        apt-get -y install monit apache2-utils
        sed -r -i "s/#?\s+with\s+start\s+delay\s+[0-9]+\s+.+/    with start delay 240/" /etc/monit/monitrc
        read -p "Enter e-mail for monit: " frommonit
        read -p "Enter username (to sign in monit and munin): " usermonit
        read -p "Enter password (to sign in monit and munin): " passmonit
        echo "set mailserver localhost" > /etc/monit/conf.d/system-services
        echo "" >> /etc/monit/conf.d/system-services
        echo "set mail-format {" >> /etc/monit/conf.d/system-services
        echo "    from: $frommonit" >> /etc/monit/conf.d/system-services
        echo "    subject: monit alert -- \$EVENT \$SERVICE" >> /etc/monit/conf.d/system-services
        echo "    message: \$EVENT Service \$SERVICE" >> /etc/monit/conf.d/system-services
        echo "    Date: \$DATE" >> /etc/monit/conf.d/system-services
        echo "    Action: \$ACTION" >> /etc/monit/conf.d/system-services
        echo "    Host: \$HOST" >> /etc/monit/conf.d/system-services
        echo "    Description: \$DESCRIPTION" >> /etc/monit/conf.d/system-services
        echo "" >> /etc/monit/conf.d/system-services
        echo "    Your faithful employee," >> /etc/monit/conf.d/system-services
        echo "    Monit" >> /etc/monit/conf.d/system-services
        echo "}" >> /etc/monit/conf.d/system-services
        echo "" >> /etc/monit/conf.d/system-services
        echo "set alert root@localhost" >> /etc/monit/conf.d/system-services
        echo "" >> /etc/monit/conf.d/system-services
        echo "set httpd port 2812 and" >> /etc/monit/conf.d/system-services
        echo "    use address localhost" >> /etc/monit/conf.d/system-services
        echo "    allow localhost" >> /etc/monit/conf.d/system-services
        echo "    allow $usermonit:\"$passmonit\"" >> /etc/monit/conf.d/system-services
        echo "" >> /etc/monit/conf.d/system-services
        echo "check system 1.1.1.1" >> /etc/monit/conf.d/system-services
        echo "    if loadavg (1min) > 4 then alert" >> /etc/monit/conf.d/system-services
        echo "    if loadavg (5min) > 2 then alert" >> /etc/monit/conf.d/system-services
        echo "    if cpu usage > 95% for 10 cycles then alert" >> /etc/monit/conf.d/system-services
        echo "    if memory usage > 75% then alert" >> /etc/monit/conf.d/system-services
        echo "    if swap usage > 25% then alert" >> /etc/monit/conf.d/system-services
        echo "" >> /etc/monit/conf.d/system-services
        echo "check filesystem rootfs with path /" >> /etc/monit/conf.d/system-services
        echo "    if space usage > 80% then alert" >> /etc/monit/conf.d/system-services
        
        echo "check process nginx with pidfile /var/run/nginx.pid" > /etc/monit/conf.d/lemp-services
        echo "    group www-data" >> /etc/monit/conf.d/lemp-services
        echo "    start program = \"/etc/init.d/nginx start\"" >> /etc/monit/conf.d/lemp-services
        echo "    stop program = \"/etc/init.d/nginx stop\"" >> /etc/monit/conf.d/lemp-services
        echo "    if failed host localhost port 80 protocol http then restart" >> /etc/monit/conf.d/lemp-services
        echo "    if 5 restarts within 5 cycles then timeout" >> /etc/monit/conf.d/lemp-services
        echo "" >> /etc/monit/conf.d/lemp-services
        echo "check process mysql with pidfile /var/run/mysqld/mysqld.pid" >> /etc/monit/conf.d/lemp-services
        echo "    start program = \"/etc/init.d/mysql start\"" >> /etc/monit/conf.d/lemp-services
        echo "    stop program = \"/etc/init.d/mysql stop\"" >> /etc/monit/conf.d/lemp-services
        echo "    if failed unixsocket /var/run/mysqld/mysqld.sock then restart" >> /etc/monit/conf.d/lemp-services
        echo "    if 5 restarts within 5 cycles then timeout" >> /etc/monit/conf.d/lemp-services
        echo "" >> /etc/monit/conf.d/lemp-services
        echo "check process php7.2-fpm with pidfile /run/php/php7.2-fpm.pid" >> /etc/monit/conf.d/lemp-services
        echo "    start program = \"/etc/init.d/php7.2-fpm start\"" >> /etc/monit/conf.d/lemp-services
        echo "    stop program = \"/etc/init.d/php7.2-fpm stop\"" >> /etc/monit/conf.d/lemp-services
        echo "    if failed unixsocket /run/php/php7.2-fpm.sock then restart" >> /etc/monit/conf.d/lemp-services
        echo "    if 5 restarts within 5 cycles then timeout" >> /etc/monit/conf.d/lemp-services
        
        htpasswd -mbc /etc/munin/.passwd $usermonit "$passmonit"
        # Add nginx configuration
        echo "server {" > /etc/nginx/sites-available/monit
        read -p "Are you want to set munin and monit as default" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            echo "        listen 80 default_server;" >> /etc/nginx/sites-available/monit
            echo "        listen [::]:80 default_server;" >> /etc/nginx/sites-available/monit
            rm /etc/nginx/sites-enabled/default
        else
            echo "        listen 80;" >> /etc/nginx/sites-available/monit
            echo "        listen [::]:80;" >> /etc/nginx/sites-available/monit
            read -p "Enter domain (admin.example.com): " sitedomain
            echo "        server_name $sitedomain;" >> /etc/nginx/sites-available/monit
        fi
        echo "        location /munin {" >> /etc/nginx/sites-available/monit
        echo "              alias /var/cache/munin/www;" >> /etc/nginx/sites-available/monit
        echo "              autoindex on;" >> /etc/nginx/sites-available/monit
        echo "              auth_basic \"Munin Statistics\";" >> /etc/nginx/sites-available/monit
        echo "              auth_basic_user_file /etc/munin/.passwd;" >> /etc/nginx/sites-available/monit
        echo "        }" >> /etc/nginx/sites-available/monit
        echo "        location /monit/ {" >> /etc/nginx/sites-available/monit
        echo "              rewrite ^/monit/(.*) /\$1 break;" >> /etc/nginx/sites-available/monit
        echo "              # proxy_ignore_client_abort on;" >> /etc/nginx/sites-available/monit
        echo "              proxy_pass http://127.0.0.1:2812;" >> /etc/nginx/sites-available/monit
        echo "              proxy_set_header Host \$host;" >> /etc/nginx/sites-available/monit
        echo "        }" >> /etc/nginx/sites-available/monit
        echo "        root /var/www/html;" >> /etc/nginx/sites-available/monit
        echo "        index index.html index.htm index.nginx-debian.html;" >> /etc/nginx/sites-available/monit
        echo "        location / {" >> /etc/nginx/sites-available/monit
        echo "                try_files \$uri \$uri/ =404;" >> /etc/nginx/sites-available/monit
        echo "        }" >> /etc/nginx/sites-available/monit
        echo "}" >> /etc/nginx/sites-available/monit
        ln -s /etc/nginx/sites-available/monit /etc/nginx/sites-enabled/monit
        echo '----------------------------------'
        echo ' Done, please reboot the server'
        echo '----------------------------------'
        ;;
    8) 
        read -p "Enter user name: " user
        adduser $user
        usermod -aG sudo $user
        sed -r -i "s/#?\s*PasswordAuthentication\s+.+/PasswordAuthentication no/" /etc/ssh/sshd_config
        sed -r -i "s/#?\s*PermitRootLogin\s+.+/PermitRootLogin no/" /etc/ssh/sshd_config
        sed -r -i "s/#?\s*PubkeyAuthentication\s+.+/PubkeyAuthentication yes/" /etc/ssh/sshd_config
        sed -r -i "s/#?\s*ChallengeResponseAuthentication\s+.+/ChallengeResponseAuthentication no/" /etc/ssh/sshd_config
        # Copy SSH key from root to user
        read -p "Are you want to copy SSH key from root to $user?" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            mkdir /home/$user/.ssh
            cp ~/.ssh/authorized_keys /home/$user/.ssh/authorized_keys
            chmod 600 /home/$user/.ssh/authorized_keys
            chmod 700 /home/$user/.ssh
            chown -R $user:$user /home/$user/.ssh
        fi
        # Change SSH port
        read -p "Are you want to change SSH port?" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
            read -p "Enter port (2332): " sshport
            sed -r -i "s/#?\s*Port\s+.+/Port $sshport/" /etc/ssh/sshd_config
            ufw allow $sshport
            ufw delete allow OpenSSH
        fi
        echo '----------------------------------'
        echo ' Done, please logout and login'
        echo '----------------------------------'
        /etc/init.d/ssh restart
        ;;
    0)
        ;;
    *) 
        echo "Invalid option"
        ;;
esac
