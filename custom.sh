#!/usr/bin/env bash

# if custom db provided import, put files in folder
  echo "11. need import db"
  if [[ ${CUSTOM_DB} ]]; then
    if [[ ${MYSQL_USER} -eq '' ]]; then
        MYSQL_USER='drupal';
    fi
    if [[ ${MYSQL_HOST} -eq '' ]]; then
        MYSQL_HOST='localhost';
    fi
    if [[ ${MYSQL_DATABASE} -eq '' ]]; then
        MYSQL_DATABASE='drupal';
    fi
    www=${DRUPAL_DOCROOT}

    /usr/bin/mysqld_safe --skip-syslog &
    if [[ $? -ne 0 ]]; then
      echo "ERROR: mysql will not start";
      exit;
    fi
    sleep 5s

    if [[ -f /drupal-db-pw.txt ]]; then
        echo "entro"
        MYSQL_PASSWORD=$(</drupal-db-pw.txt)
    else
        MYSQL_ROOT_PASSWORD=`pwgen -c -n -1 12`
        MYSQL_PASSWORD=`pwgen -c -n -1 12`
        # If needed to show passwords in the logs:
        #echo mysql root password: $MYSQL_ROOT_PASSWORD, drupal password: $MYSQL_PASSWORD
        echo "Generated mysql root + drupal password, see /root/.my.cnf /mysql-root-pw.txt /drupal-db-pw.txt"
        echo $MYSQL_PASSWORD > /drupal-db-pw.txt
        echo $MYSQL_ROOT_PASSWORD > /mysql-root-pw.txt
        chmod 400 /mysql-root-pw.txt /drupal-db-pw.txt
        mysqladmin -u root password $MYSQL_ROOT_PASSWORD
        mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO $MYSQL_USER@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'; FLUSH PRIVILEGES;"
        mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $MYSQL_DATABASE; GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO $MYSQL_USER@'%' IDENTIFIED BY '$MYSQL_PASSWORD'; FLUSH PRIVILEGES;"
        # allow mysql cli for root
        mv /root/.my.cnf.sample /root/.my.cnf
        sed -i "s/ADDED_BY_START.SH/$MYSQL_ROOT_PASSWORD/" /root/.my.cnf
    fi
    echo "pass ${MYSQL_PASSWORD}"

    echo "${MYSQL_USER}USER"

    echo "importing db"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --host=${MYSQL_HOST} ${MYSQL_DATABASE} < ${CUSTOM_DB}
    echo "adding files"

    if [[ ! -d $www/sites/default/files ]]; then
        mkdir $www/sites/default/files
    fi

    if [[ ${DRUPAL_VERSION} -eq "drupal-6" ]]; then
        echo "reseting admin user pass"
        mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --host=${MYSQL_HOST} ${MYSQL_DATABASE} -e'UPDATE tan_users SET PASS=MD5("${DRUPAL_ADMIN_PW}") WHERE uid=1'
        echo "enable short_open tags"
        sed -i 's/short_open_tag = Off/short_open_tag = On/g' /etc/php5/apache2/php.ini
        cp -R /files/tanta-6/* ./sites/default/files/
        cat > ./sites/default/settings.php << EOF
<?php
\$db_url = 'mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}/${MYSQL_DATABASE}';
\$db_prefix = 'tan_';
EOF
    else
    echo "reseting admin user pass for d8"
     sed -i "s/^[ \t]*'password'.*/  \'password\' => \'${MYSQL_PASSWORD}\',/" $www/sites/default/settings.php
    # allow mysql cli for root
    cd $www
    drush cr
    NEW_PW="$(php core/scripts/password-hash.sh "${DRUPAL_ADMIN_PW}" | sed -n -e 's/^.*hash: //p')"
    echo "new PASSWORD -${NEW_PW}-"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --host=${MYSQL_HOST} ${MYSQL_DATABASE} -e"UPDATE users_field_data SET PASS='${NEW_PW}' WHERE uid=1"
    echo "mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --host=${MYSQL_HOST} ${MYSQL_DATABASE} -e\"UPDATE users_field_data SET PASS='${NEW_PW}' WHERE uid=1\""
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --host=${MYSQL_HOST} ${MYSQL_DATABASE} -e"DELETE FROM cache_entity WHERE cid = 'values:user:1'";
    echo "mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --host=${MYSQL_HOST} ${MYSQL_DATABASE} -e\"DELETE FROM cache_entity WHERE cid = 'values:user:1'\"";
    fi

    killall mysqld


    if [[ ! -d "vendor" ]]; then
    composer install
    fi
  fi
