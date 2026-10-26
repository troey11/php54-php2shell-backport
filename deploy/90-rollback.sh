#!/bin/bash
# ROLLBACK — reinstall the original packages and config from the rollback set.
set -u
. "$(dirname "$0")/config.sh"
rm -f /usr/sbin/policy-rc.d   # in case 10-install.sh was interrupted
export UCF_FORCE_CONFFOLD=1 DEBIAN_FRONTEND=noninteractive
( cd "$ROLLBACK_DIR" && sha256sum -c --quiet SHA256SUMS ) || { echo "Rollback checksums do NOT match — stopping"; exit 1; }
"$ROLLBACK_DIR/ROLLBACK.sh"
dpkg-query -W -f='${Package} ${Version}\n' $PACKAGES
echo "Done. Run 20-verify.sh to compare HTTP status (the max_multipart_body_parts check is expected to FAIL after rollback)."
