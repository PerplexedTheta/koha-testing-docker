#!/bin/bash

set -e

export BUILD_DIR=/kohadevbox
export TEMP=/tmp

# Handy variables
export KOHA_INTRANET_FQDN=${KOHA_INTRANET_PREFIX}${KOHA_INSTANCE}${KOHA_INTRANET_SUFFIX}${KOHA_DOMAIN}
export KOHA_OPAC_FQDN=${KOHA_OPAC_PREFIX}${KOHA_INSTANCE}${KOHA_OPAC_SUFFIX}${KOHA_DOMAIN}

if [ -z ${KOHA_OPAC_URL} ]; then
    export KOHA_OPAC_URL=http://${KOHA_OPAC_FQDN}:${KOHA_OPAC_PORT}
fi
if [ -z ${KOHA_INTRANET_URL} ]; then
    export KOHA_INTRANET_URL=http://${KOHA_INTRANET_FQDN}:${KOHA_INTRANET_PORT}
fi

export PATH=${PATH}:/kohadevbox/bin:/kohadevbox/koha/node_modules/.bin/:/kohadevbox/node_modules/.bin/

# Node stuff
export NODE_PATH=/kohadevbox/node_modules:$NODE_PATH

if [ "${DEBUG_RUN}" = "yes" ]; then
    echo "DEBUG_RUN_URL=$DEBUG_RUN_URL";
    wget ${DEBUG_RUN_URL} -O /tmp/run.sh
    bash /tmp/run.sh
    exit
fi


# Set a fixed hostname
echo "kohadevbox" > /etc/hostname

# Early exit if SYNC_REPO is not correctly set
# Assuming than about.pl will not be removed!
if [ ! -f "${BUILD_DIR}/koha/about.pl" ]; then
    echo "The environment variable SYNC_REPO does not point to a valid Koha git repository."
    exit 2
fi

# Latest Depends
if [ "${CPAN}" = "yes" ]; then
    echo "Installing latest versions of dependancies from cpan"
    apt update
    apt install -y cpanoutdated
    cpan-outdated --exclude-core -p | cpanm
fi

# Install everything in Koha's cpanfile, may include libs for extra patches being tested
if [ "${INSTALL_MISSING_FROM_CPANFILE}" = "yes" ]; then
    cpanm --skip-installed --installdeps ${BUILD_DIR}/koha/
fi

append_if_absent()
{
    local string=$1
    local file=$2

    if ! grep -Fxq "$string" "$file"; then
        echo $string >> $file
    fi
}

append_if_absent "127.0.0.1 kohadevbox" /etc/hosts
hostname kohadevbox


# Remove packages for developers if it's a Jenkins run (CI_RUN=1)
if [ "${CI_RUN}" = "yes" ]; then
    apt-get -y remove \
      libcarp-always-perl \
      libgit-repository-perl \
      libmemcached-tools \
      libperl-critic-perl \
      libtest-perl-critic-perl \
      libtest-perl-critic-progressive-perl \
      libfile-chdir-perl \
      libdata-printer-perl \
      pmtools
fi

# debug failing apache --restart
sudo service --status-all

# Clone before calling cp_debian_files.pl
if [ "${DEBUG_GIT_REPO_MISC4DEV}" = "yes" ]; then
    rm -rf ${BUILD_DIR}/misc4dev
    git clone -b ${DEBUG_GIT_REPO_MISC4DEV_BRANCH} ${DEBUG_GIT_REPO_MISC4DEV_URL} ${BUILD_DIR}/misc4dev
fi

if [ "${DEBUG_GIT_REPO_QATESTTOOLS}" = "yes" ]; then
    rm -rf ${BUILD_DIR}/qa-test-tools
    git clone -b ${DEBUG_GIT_REPO_QATESTTOOLS_BRANCH} ${DEBUG_GIT_REPO_QATESTTOOLS_URL} ${BUILD_DIR}/qa-test-tools
fi

# Make sure we use the files from the git clone for creating the instance
perl ${BUILD_DIR}/misc4dev/cp_debian_files.pl \
            --instance          ${KOHA_INSTANCE} \
            --koha_dir          ${BUILD_DIR}/koha \
            --gitify_dir        ${BUILD_DIR}/gitify

# Wait for the DB server startup
while ! nc -z db 3306; do sleep 1; done

# TODO: Have bugs pushed so all this is a koha-create parameter
echo "${KOHA_INSTANCE}:koha_${KOHA_INSTANCE}:${KOHA_DB_PASSWORD}:koha_${KOHA_INSTANCE}" > /etc/koha/passwd
# TODO: Get rid of this hack with the relevant bug
echo "[client]"                   > /etc/mysql/koha-common.cnf
echo "host     = ${DB_HOSTNAME}" >> /etc/mysql/koha-common.cnf
echo "user     = root"           >> /etc/mysql/koha-common.cnf
echo "password = password"       >> /etc/mysql/koha-common.cnf


echo "[client]"                          > /etc/mysql/koha_${KOHA_INSTANCE}.cnf
echo "host     = ${DB_HOSTNAME}"        >> /etc/mysql/koha_${KOHA_INSTANCE}.cnf
echo "user     = koha_${KOHA_INSTANCE}" >> /etc/mysql/koha_${KOHA_INSTANCE}.cnf
echo "password = ${KOHA_DB_PASSWORD}"   >> /etc/mysql/koha_${KOHA_INSTANCE}.cnf

# Get rid of Apache warnings
append_if_absent "ServerName kohadevbox"        /etc/apache2/apache2.conf
append_if_absent "Listen ${KOHA_INTRANET_PORT}" /etc/apache2/ports.conf
append_if_absent "Listen ${KOHA_OPAC_PORT}"     /etc/apache2/ports.conf

# Pull the names of the environment variables to substitute from defaults.env and convert them to a string of the format "$VAR1:$VAR2:$VAR3", etc.
VARS_TO_SUB=`cut -d '=' -f1 ${BUILD_DIR}/templates/defaults.env  | tr '\n' ':' | sed -e 's/:/:$/g' | awk '{print "$"$1}' | sed -e 's/:\$$//'`
# Add additional vars to sub from this script that are not in defaults.env
VARS_TO_SUB="\$BUILD_DIR:$VARS_TO_SUB";

envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/root_bashrc           > /root/.bashrc
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/vimrc                 > /root/.vimrc
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bash_aliases          > /root/.bash_aliases
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/koha-conf-site.xml.in > /etc/koha/koha-conf-site.xml.in
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/koha-sites.conf       > /etc/koha/koha-sites.conf
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/sudoers               > /etc/sudoers.d/${KOHA_INSTANCE}

# bin
mkdir -p ${BUILD_DIR}/bin
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bin/dbic > ${BUILD_DIR}/bin/dbic
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bin/flush_memcached > ${BUILD_DIR}/bin/flush_memcached
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bin/bisect_with_test > ${BUILD_DIR}/bin/bisect_with_test

# Make sure things are executable on /bin.
chmod +x ${BUILD_DIR}/bin/*

koha-create --request-db ${KOHA_INSTANCE} --memcached-servers memcached:11211

envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/vimrc > /var/lib/koha/${KOHA_INSTANCE}/.vimrc
chown "${KOHA_INSTANCE}-koha" "/var/lib/koha/${KOHA_INSTANCE}/.vimrc"

if [ -d "${BUILD_DIR}/howto" ]
then
    echo "Install Koha-how-to"
    rm -f ${BUILD_DIR}/koha/how-to.pl ${BUILD_DIR}/koha/koha-tmpl/intranet-tmpl/prog/en/modules/how-to.tt
    ln -s ${BUILD_DIR}/howto/how-to.pl ${BUILD_DIR}/koha/how-to.pl
    ln -s ${BUILD_DIR}/howto/how-to.tt ${BUILD_DIR}/koha/koha-tmpl/intranet-tmpl/prog/en/modules/how-to.tt
fi

echo "[cypress] Make the pre-built cypress available to the instance user [HACK]"

mkdir -p "/var/lib/koha/${KOHA_INSTANCE}/.cache" \
  && echo "    [*] Created cache dir /var/lib/koha/${KOHA_INSTANCE}/.cache/" \
  || echo "    [x] Error creating cache dir /var/lib/koha/${KOHA_INSTANCE}/.cache/"

chown -R "${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha" "/var/lib/koha/${KOHA_INSTANCE}/.cache/" \
  && echo "    [*] Chowning /var/lib/koha/${KOHA_INSTANCE}/.cache/" \
  || echo "    [x] Error chowning cache dir /var/lib/koha/${KOHA_INSTANCE}/.cache/"

ln -s /kohadevbox/Cypress "/var/lib/koha/${KOHA_INSTANCE}/.cache/" \
  && echo "    [*] Cypress dir linked to /var/lib/koha/${KOHA_INSTANCE}/.cache/" \
  || echo "    [x] Error linking Cypress dir to /var/lib/koha/${KOHA_INSTANCE}/.cache/"

# Fix UID if not empty, and differs from 1000 (Docker's default for the next UID)
if [[ ! -z "${LOCAL_USER_ID}" && "${LOCAL_USER_ID}" != "1000" ]]; then
    usermod -o -u ${LOCAL_USER_ID} "${KOHA_INSTANCE}-koha"

    if [[ "${SKIP_CYPRESS_CHOWN}" != "yes" ]]; then
        chown -R "${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha" "/kohadevbox/Cypress" \
          && echo "    [*] Cypress dir chowned correctly" \
          || echo "    [x] Error running chown on Cypress dir"
    fi

    # Fix permissions due to UID change
    chown -R "${KOHA_INSTANCE}-koha" "/var/cache/koha/${KOHA_INSTANCE}"
    chown -R "${KOHA_INSTANCE}-koha" "/var/lib/koha/${KOHA_INSTANCE}"
    chown -R "${KOHA_INSTANCE}-koha" "/var/lock/koha/${KOHA_INSTANCE}"
    chown -R "${KOHA_INSTANCE}-koha" "/var/log/koha/${KOHA_INSTANCE}"
    chown -R "${KOHA_INSTANCE}-koha" "/var/run/koha/${KOHA_INSTANCE}"
    chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/misc4dev
    chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/gitify
    chown -R "${KOHA_INSTANCE}-koha" ${BUILD_DIR}/qa-test-tools
fi

if [[ ${SKIP_L10N} != "yes" ]]; then
    if [[ ! -z "$KOHA_IMAGE" && ! "$KOHA_IMAGE" =~ ^main ]]; then
        l10n_branch=${KOHA_IMAGE:0:5}
    else
        l10n_branch="main"
    fi

    set +e

    echo "[koha-l10n] Handling koha-l10n as requested"

    if [ ! -d "$BUILD_DIR/koha/misc/translator/po" ]; then
        echo "    [*] Cloning koha-l10n into misc/translator/po"
        sudo koha-shell ${KOHA_INSTANCE} -c "\
            git clone --depth 1 --branch ${l10n_branch} https://gitlab.com/koha-community/koha-l10n.git $BUILD_DIR/koha/misc/translator/po"
    elif [ -d "$BUILD_DIR/koha/misc/translator/po/.git" ]; then
        echo "    [*] Chowning po files (safety measure)"
        chown -R "${KOHA_INSTANCE}-koha" "$BUILD_DIR/koha/misc/translator/po"
        echo "    [*] Fetching koha-l10n"
        sudo koha-shell ${KOHA_INSTANCE} -c "\
            git config --global --add safe.directory $BUILD_DIR/koha/misc/translator/po ; \
            git -C $BUILD_DIR/koha/misc/translator/po fetch origin ; \
            git -C $BUILD_DIR/koha/misc/translator/po checkout -B ${l10n_branch} origin/${l10n_branch}"
    fi

    set -e
else
    echo "[koha-l10n] Skipping"
fi

echo "[API logging] Set TRACE to API log4perl config"
sed -i 's/log4perl.logger.api = WARN, API/log4perl.logger.api = TRACE, API/' /etc/koha/sites/${KOHA_INSTANCE}/log4perl.conf \
  && echo "    [*] TRACE set for the API log4perl configuration" \
  || echo "    [x] Error setting TRACE for the API log4perl configuration"

echo "[git] Setting up Git on the instance user"
echo "    [*] Generating /var/lib/koha/${KOHA_INSTANCE}/.gitconfig"
sudo koha-shell ${KOHA_INSTANCE} -c "\
    cp ${BUILD_DIR}/templates/gitconfig /var/lib/koha/${KOHA_INSTANCE}/.gitconfig"

echo "    [*] General setup"
sudo koha-shell ${KOHA_INSTANCE} -c "\
    cd ${BUILD_DIR}/koha ; \
    git config --global --add safe.directory ${BUILD_DIR}/koha ; \
    git config --global user.name  \"${GIT_USER_NAME}\" ; \
    git config --global user.email \"${GIT_USER_EMAIL}\" ; \
    git config bz.default-tracker bugs.koha-community.org ; \
    git config bz.default-product Koha ; \
    git config --global bz-tracker.bugs.koha-community.org.path /bugzilla3 ; \
    git config --global bz-tracker.bugs.koha-community.org.https true ; \
    git config --global core.whitespace trailing-space,space-before-tab ; \
    git config --global apply.whitespace fix ; \
    git config --global bz-tracker.bugs.koha-community.org.bz-user     \"${GIT_BZ_USER}\" ; \
    git config --global bz-tracker.bugs.koha-community.org.bz-password \"${GIT_BZ_PASSWORD}\" "

GIT_BASE_DIR=${BUILD_DIR}/koha
if [ "${GIT_WORKTREE_SOURCE}" != "" ]; then
    # Git worktree!
    echo "    [!] Detected worktree: pointing to '${GIT_WORKTREE_SOURCE}'"
    GIT_BASE_DIR=${GIT_WORKTREE_SOURCE}
    sudo koha-shell ${KOHA_INSTANCE} -c "\
        cd ${BUILD_DIR}/koha ; \
        git config --global --add safe.directory ${GIT_WORKTREE_SOURCE}"
    echo "    [*] Added '${GIT_WORKTREE_SOURCE}' to safe directories"
fi

if [ "${GIT_WORKTREE_SOURCE}" != "" ]; then
    # Skip for worktrees
    echo "    [!] Skipping hooks setup"
else
    echo "    [*] Installing and setting hooks (${GIT_BASE_DIR})"
    sudo koha-shell ${KOHA_INSTANCE} -c "\
        mkdir -p ${GIT_BASE_DIR}/.git/hooks/ktd ; \
        cp ${BUILD_DIR}/git_hooks/* ${GIT_BASE_DIR}/.git/hooks/ktd ; \
        cd ${GIT_BASE_DIR} ; \
        git config --local core.hooksPath .git/hooks/ktd"
fi

# This needs to be done ONCE koha-create has run (i.e. kohadev-koha user exists)
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/apache2_envvars > /etc/apache2/envvars

# gitify instance
cd ${BUILD_DIR}/gitify
./koha-gitify ${KOHA_INSTANCE} "/kohadevbox/koha"
cd ${BUILD_DIR}

koha-enable ${KOHA_INSTANCE} 
a2ensite ${KOHA_INSTANCE}.conf

cp /kohadevbox/koha/package.json /kohadevbox
cp /kohadevbox/koha/yarn.lock    /kohadevbox
yarn install --modules-folder /kohadevbox/node_modules

# Update /etc/hosts so the www tests can run
echo "127.0.0.1    ${KOHA_OPAC_FQDN} ${KOHA_INTRANET_FQDN}" >> /etc/hosts

envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/instance_bashrc > /var/lib/koha/${KOHA_INSTANCE}/.bashrc
envsubst "$VARS_TO_SUB" < ${BUILD_DIR}/templates/bash_aliases    > /var/lib/koha/${KOHA_INSTANCE}/.bash_aliases

if [ "${KOHA_ELASTICSEARCH}" = "yes" ]; then
    ES_FLAG="--elasticsearch"
fi

if [ "${USE_EXISTING_DB}" = "yes" ]; then
    USE_EXISTING_DB_FLAG="--use-existing-db"
fi

perl ${BUILD_DIR}/misc4dev/do_all_you_can_do.pl \
            --instance          ${KOHA_INSTANCE} ${ES_FLAG} ${USE_EXISTING_DB_FLAG} \
            --userid            ${KOHA_USER} \
            --password          ${KOHA_PASS} \
            --marcflavour       ${KOHA_MARC_FLAVOUR} \
            --koha_dir          ${BUILD_DIR}/koha \
            --opac-base-url     ${KOHA_OPAC_URL} \
            --intranet-base-url ${KOHA_INTRANET_URL} \
            --gitify_dir        ${BUILD_DIR}/gitify

# Stop apache2
service apache2 stop

echo "[logs] Chowning logs"
chown -R "${KOHA_INSTANCE}-koha:${KOHA_INSTANCE}-koha" "/var/log/koha/${KOHA_INSTANCE}" \
  && echo "    [*] Success chowning /var/log/koha/${KOHA_INSTANCE}" \
  || echo "    [x] Error chowning cache dir /var/log/koha/${KOHA_INSTANCE}"

if [ "${ENABLE_PLUGINS}" = "yes" ]; then

    echo "[plugins] Installing plugins"

    PLUGINS_STRING=""
    counter=0

    for plugin_dir in $(find ${BUILD_DIR}/plugins -mindepth 1 -maxdepth 1 -type d); do

        echo "    [*] Found: ${plugin_dir}"

	    entry=" <pluginsdir>${BUILD_DIR}/plugins/$(basename $plugin_dir)</pluginsdir>"

        # Append the new plugin's entry
        if [ "${counter}" -ge 1 ]; then
	        PLUGINS_STRING="${PLUGINS_STRING}\n${entry}"
        else
	        PLUGINS_STRING="${entry}"
        fi

        counter=$((counter+1))
    done

    flush_memcached
    # replace the placeholder with the plugins entries
    sed -i "s# <!--pluginsdir>YOUR_PLUGIN_DIR_HERE</pluginsdir-->#$(echo "$PLUGINS_STRING")#" /etc/koha/sites/kohadev/koha-conf.xml
    # run the plugins installer
    perl ${BUILD_DIR}/koha/misc/devel/install_plugins.pl
    echo "    [*] Plugins loaded!"
fi

# Enable and start koha-plack and koha-z3950-responder
koha-plack           --enable ${KOHA_INSTANCE}
koha-z3950-responder --enable ${KOHA_INSTANCE}
service koha-common start

# Start apache and rabbitmq-server
service apache2 start
service rabbitmq-server start || true # Don't crash if rabbitmq-server didn't start

touch /ktd_ready
echo "koha-testing-docker has started up and is ready to be enjoyed!"

# if KOHA_PROVE_CPUS is not set, then use nproc
if [ -z ${KOHA_PROVE_CPUS} ]; then
    KOHA_PROVE_CPUS=`nproc`
fi

if [ "$RUN_TESTS_AND_EXIT" = "yes" ]; then

    export KOHA_TESTING=1

    if [ "${TEST_DB_UPGRADE}" = "yes" ]; then

        # Note that --run-all-tests includes this
        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-db-upgrade-only

    fi

    if [ ${COVERAGE} ]; then

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-all-tests --with-coverage

    elif [ "$TEST_SUITE" = "light" ]; then

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-light-test-suite

    elif [ "$TEST_SUITE" = "es-only" ]; then # test elastic-search only

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-elastic-tests-only

    elif [ "$TEST_SUITE" = "selenium-only" ]; then # selenium tests only

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-selenium-tests-only

    elif [ "$TEST_SUITE" = "db-compare-only" ]; then # update the DB, dbic, DB structure

        if [ -z ${DB_COMPARE_WITH} ]; then
            echo "ERROR: \$TEST_SUITE=db-compare-only requires \$DB_COMPARE_WITH set"
            exit 2
        fi

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-db-compare-only --compare-with "${DB_COMPARE_WITH}"

    elif [ "$TEST_SUITE" = "specific-tests" ]; then # run specific tests

        if [ -z ${TESTS_TO_RUN} ]; then
            echo "ERROR: \$TEST_SUITE=specific-tests requires \$TESTS_TO_RUN set"
            exit 2
        fi

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-only "${TESTS_TO_RUN}"

    else

        perl ${BUILD_DIR}/misc4dev/run_tests.pl --koha-dir=${BUILD_DIR}/koha --run-all-tests

    fi

else

# start koha-reload-starman, if we have inotify installed
#    if [ -f "/usr/bin/inotifywait" ]; then
#        daemon  --verbose=1 \
#            --name=reload-starman \
#            --respawn \
#            --delay=15 \
#            --pidfiles=/var/run/koha/kohadev/ -- /kohadevbox/koha-reload-starman
#    fi

    # TODO: We could use supervise as the main loop
    /bin/bash -c "trap : TERM INT; sleep infinity & wait"
fi
