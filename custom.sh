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
        if [[ ! -d ./sites/default/files ]]; then
            mkdir ./sites/default/files
        fi
        cp -R /files/tanta-6/* ./sites/default/files/
        chown -R www-data.www-data ./sites/default/files/
        if [ ! -f 'sites/default/settings.php' ]; then
            touch ./sites/default/settings.php
        fi
        cat > ./sites/default/settings.php << EOF
<?php
\$db_url = 'mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}/${MYSQL_DATABASE}';
\$db_prefix = 'tan_';
EOF
if [[ ! -f .htaccess ]]; then
        echo "add .htaccess"
        cat > .htaccess << EOF
##
## Apache/PHP/Drupal settings:
##
#
## Protect files and directories from prying eyes.
#<FilesMatch "\.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl|svn-base)$|^(code-style\.pl|Entries.*|Repository|Root|Tag|Template|all-wcprops|entries|format)$">
#  Order allow,deny
#</FilesMatch>
#
## Don't show directory listings for URLs which map to a directory.
#Options -Indexes
#
## Follow symbolic links in this directory.
#Options +FollowSymLinks
#
## Make Drupal handle any 404 errors.
#ErrorDocument 404 /index.php
#
## Force simple error message for requests for non-existent favicon.ico.
#<Files favicon.ico>
#  # There is no end quote below, for compatibility with Apache 1.3.
#  ErrorDocument 404 "The requested file favicon.ico was not found.
#</Files>
#
## Set the default handler.
#DirectoryIndex index.php
#
## Override PHP settings. More in sites/default/settings.php
## but the following cannot be changed at runtime.
#
## PHP 4, Apache 1.
#<IfModule mod_php4.c>
#  php_value magic_quotes_gpc                0
#  php_value register_globals                0
#  php_value session.auto_start              0
#  php_value mbstring.http_input             pass
#  php_value mbstring.http_output            pass
#  php_value mbstring.encoding_translation   0
#</IfModule>
#
## PHP 4, Apache 2.
#<IfModule sapi_apache2.c>
#  php_value magic_quotes_gpc                0
#  php_value register_globals                0
#  php_value session.auto_start              0
#  php_value mbstring.http_input             pass
#  php_value mbstring.http_output            pass
#  php_value mbstring.encoding_translation   0
#</IfModule>
#
## PHP 5, Apache 1 and 2.
#<IfModule mod_php5.c>
#  php_value magic_quotes_gpc                0
#  php_value register_globals                0
#  php_value session.auto_start              0
#  php_value mbstring.http_input             pass
#  php_value mbstring.http_output            pass
#  php_value mbstring.encoding_translation   0
#</IfModule>
#
## Requires mod_expires to be enabled.
#<IfModule mod_expires.c>
#  # Enable expirations.
#  ExpiresActive On
#
#  # Cache all files for 2 weeks after access (A).
#  ExpiresDefault A1209600
#
#  <FilesMatch \.php$>
#    # Do not allow PHP scripts to be cached unless they explicitly send cache
#    # headers themselves. Otherwise all scripts would have to overwrite the
#    # headers set by mod_expires if they want another caching behavior. This may
#    # fail if an error occurs early in the bootstrap process, and it may cause
#    # problems if a non-Drupal PHP file is installed in a subdirectory.
#    ExpiresActive Off
#  </FilesMatch>
#</IfModule>
#
## Various rewrite rules.
#<IfModule mod_rewrite.c>
#  RewriteEngine on
#
#  # If your site can be accessed both with and without the 'www.' prefix, you
#  # can use one of the following settings to redirect users to your preferred
#  # URL, either WITH or WITHOUT the 'www.' prefix. Choose ONLY one option:
#  #
#  # To redirect all users to access the site WITH the 'www.' prefix,
#  # (http://example.com/... will be redirected to http://www.example.com/...)
#  # adapt and uncomment the following:
#  # RewriteCond %{HTTP_HOST} ^example\.com$ [NC]
#  # RewriteRule ^(.*)$ http://www.example.com/$1 [L,R=301]
#  #
#  # To redirect all users to access the site WITHOUT the 'www.' prefix,
#  # (http://www.example.com/... will be redirected to http://example.com/...)
#  # uncomment and adapt the following:
#  # RewriteCond %{HTTP_HOST} ^www\.example\.com$ [NC]
#  # RewriteRule ^(.*)$ http://example.com/$1 [L,R=301]
#
#  # Modify the RewriteBase if you are using Drupal in a subdirectory or in a
#  # VirtualDocumentRoot and the rewrite rules are not working properly.
#  # For example if your site is at http://example.com/drupal uncomment and
#  # modify the following line:
#  # RewriteBase /drupal
#  #
#  # If your site is running in a VirtualDocumentRoot at http://example.com/,
#  # uncomment the following line:
#  # RewriteBase /
#
#  Redirect 301 /el-blog-de-tanta http://blog.tantacom.com/
#
#  # Rewrite URLs of the form 'x' to the form 'index.php?q=x'.
#  RewriteCond %{REQUEST_FILENAME} !-f
#  RewriteCond %{REQUEST_FILENAME} !-d
#  RewriteCond %{REQUEST_URI} !=/favicon.ico
#  RewriteRule ^(.*)$ index.php?q=$1 [L,QSA]
#</IfModule>
#
## $Id$
<IfModule mod_rewrite.c>
 Redirect 301 /el-blog-de-tanta http://blog.tantacom.com/
</IfModule>
EOF
fi
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
  fi
