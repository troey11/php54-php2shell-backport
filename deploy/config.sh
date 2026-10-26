# Deployment settings — edit before use. Sourced by the other deploy scripts.

# Directory containing the patched .debs (output of build/build.sh)
DEBS=${DEBS:-/srv/php-build/root/build}
# Rollback set created by backup/repack-installed.sh
ROLLBACK_DIR=${ROLLBACK_DIR:-/root/php-rollback-CHANGE-ME}
# Working directory for baseline/logs
WORK=${WORK:-/root/php-cve-install}

# Packages to replace: only list packages that are installed on this host.
PACKAGES=${PACKAGES:-"libapache2-mod-php5 php5-cli php5-common php5-curl php5-gd php5-mysql"}
NEWVER=5.4.6-1ubuntu1.8+cve2026.1
ARCH=${ARCH:-i386}

# Local base URL of the web server and the app paths to compare before/after
BASE_URL=${BASE_URL:-http://127.0.0.1}
APPS=${APPS:-"app1 app2"}
# Document root used to drop a temporary version-probe file (removed immediately)
DOCROOT=${DOCROOT:-/var/www}
APACHE_ERROR_LOG=${APACHE_ERROR_LOG:-/var/log/apache2/error.log}
