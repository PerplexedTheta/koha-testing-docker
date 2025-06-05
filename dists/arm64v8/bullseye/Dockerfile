FROM arm64v8/debian:bullseye

# File Author / Maintainer
LABEL maintainer="tomascohen@theke.io"

ENV PATH /usr/bin:/bin:/usr/sbin:/sbin
ENV DEBIAN_FRONTEND noninteractive

ENV REFRESHED_AT 2023-04-04

# Install apache2 and testting deps
# netcat: used for checking the DB is up
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt-get -y install \
      apache2 \
      build-essential \
      codespell \
      cpanminus \
      git \
      tig \
      libcarp-always-perl \
      libgit-repository-perl \
      libmemcached-tools \
      libmodule-install-perl \
      libperl-critic-perl \
      libtest-differences-perl \
      libtest-perl-critic-perl \
      libtest-perl-critic-progressive-perl \
      libfile-chdir-perl \
      libdata-printer-perl \
      pmtools \
      locales \
      netcat \
      python-gdbm \
      vim \
      nano \
      tmux \
      wget \
      curl \
      apt-transport-https \
      mlocate \
      iproute2 \
   && rm -rf /var/cache/apt/archives/* \
   && rm -rf /var/lib/apt/lists/*

# Set locales
RUN    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && dpkg-reconfigure locales \
    && /usr/sbin/update-locale LANG=en_US.UTF-8

ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8

# Prepare apache configuration
RUN a2dismod mpm_event
RUN a2dissite 000-default
RUN a2enmod rewrite \
            headers \
            proxy_http \
            cgi

# Add Koha development repositories
RUN echo "deb http://debian.koha-community.org/koha-staging dev main" >> /etc/apt/sources.list.d/koha.list
RUN wget -q -O- http://debian.koha-community.org/koha/gpg.asc | apt-key add -

# Install koha-common
RUN apt-get -y update \
   && apt-cache policy koha-common \
   && apt-cache policy libmojolicious-perl \
   && apt-cache policy libjson-validator-perl \
   && apt-cache policy libmojolicious-plugin-openapi-perl \
   && apt-cache policy libyaml-libyaml-perl \
   && apt-get -y install \
         koha-common \
   && /etc/init.d/koha-common stop \
   && rm -rf /var/cache/apt/archives/* \
   && rm -rf /var/lib/apt/lists/* \
   && rm -rf /usr/share/koha/misc/translator/po/* # Do not embed PO files

RUN mkdir /kohadevbox
WORKDIR /kohadevbox

# Install testing extras, packages and cpan
RUN apt-get -y update \
   && apt-get -y install \
         perltidy \
         libexpat1-dev \
         libtemplate-plugin-gettext-perl \
         libdevel-cover-perl \
         libmoosex-attribute-env-perl \
         libtest-dbix-class-perl \
         libtap-harness-junit-perl \
         libtext-csv-unicode-perl \
         libdevel-cover-report-clover-perl \
         libwebservice-ils-perl \
         libselenium-remote-driver-perl \
         inotify-tools \
   && rm -rf /var/cache/apt/archives/* \
   && rm -rf /var/lib/apt/lists/*

# Add nodejs repo
RUN wget -O- -q https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor \
      | tee /usr/share/keyrings/nodesource.gpg >/dev/null \
   && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

# Add yarn repo
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
   && wget -O- -q https://dl.yarnpkg.com/debian/pubkey.gpg \
      | gpg --dearmor \
      | tee /usr/share/keyrings/yarnkey.gpg >/dev/null \
   && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | tee /etc/apt/sources.list.d/yarn.list

# Install Node.js and Yarn
RUN apt-get update \
   && apt-cache policy nodejs \
   && apt-cache policy yarn \
   && apt-get -y install nodejs yarn \
   && rm -rf /var/cache/apt/archives/* \
   && rm -rf /var/lib/apt/lists/*

# Install some tool
RUN yarn global add gulp-cli

# Embed /kohadevbox/node_modules
RUN cd /kohadevbox \
    && wget -q https://gitlab.com/koha-community/Koha/-/raw/main/package.json?inline=false -O package.json \
    && wget -q https://gitlab.com/koha-community/Koha/-/raw/main/yarn.lock?inline=false -O yarn.lock \
    && yarn install --modules-folder /kohadevbox/node_modules \
    && mv /root/.cache/Cypress /kohadevbox && chown -R 1000 /kohadevbox/Cypress \
    && rm -f package.json yarn.lock

# Add git-bz
RUN cd /usr/local/share \
    && git clone --depth 1 --branch apply_on_cascade https://gitlab.com/koha-community/git-bz git-bz \
    && ln -s /usr/local/share/git-bz/git-bz /usr/bin/git-bz

# Clone helper repositories
RUN cd /kohadevbox \
    && git clone https://gitlab.com/koha-community/koha-misc4dev.git   misc4dev \
    && git clone https://gitlab.com/koha-community/koha-gitify.git     gitify \
    && git clone https://gitlab.com/koha-community/qa-test-tools.git   qa-test-tools \
    && chown -R 1000 misc4dev \
                     gitify \
                     qa-test-tools

# How-to
RUN cd /kohadevbox \
    && git clone https://gitlab.com/koha-community/koha-howto.git howto \
    && apt-get update \
    && apt-get -y install \
        bugz \
    && rm -rf /var/cache/apt/archives/* \
    && rm -rf /var/lib/apt/lists/*

# cypress tests
RUN apt-get update \
    && apt-get -y install \
        libgtk2.0-0\
        libgtk-3-0\
        libgbm-dev\
        libnotify-dev\
        libgconf-2-4\
        libnss3\
        libxss1\
        libasound2\
        libxtst6\
        xauth\
        xvfb \
    && rm -rf /var/cache/apt/archives/* \
    && rm -rf /var/lib/apt/lists/*

# Install temporary packages
# RUN apt-get update \
#    && apt-get -y install \
#        <PACKAGES HERE>
#    && rm -rf /var/cache/apt/archives/* \
#    && rm -rf /var/lib/apt/lists/*

VOLUME /kohadevbox/koha

COPY files/run.sh /kohadevbox
COPY files/templates /kohadevbox/templates
COPY env/defaults.env /kohadevbox/templates/defaults.env
COPY files/git_hooks /kohadevbox/git_hooks

CMD ["/bin/bash", "/kohadevbox/run.sh"]

EXPOSE 8080 8081
