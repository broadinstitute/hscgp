# use KDUX base Rails image, configure only project-specific items here
FROM singlecellportal/rails-baseimage:1.1.2

# install mcrypt for updating user whitelist from dbGap
RUN apt-get update && apt-get install -y -qq --no-install-recommends mcrypt
RUN apt-get install -y -qq git curl iputils-ping
# Set ruby version
RUN bash -lc 'rvm --default use ruby-2.6.6'
RUN bash -lc 'rvm rvmrc warning ignore /home/app/webapp/Gemfile'

# Set up project dir, install gems, set up script to migrate database and precompile static assets on run
RUN mkdir /home/app/webapp
RUN ping -c 3 github.com
COPY Gemfile /home/app/webapp/Gemfile
COPY Gemfile.lock /home/app/webapp/Gemfile.lock
WORKDIR /home/app/webapp
RUN bundle install

#RUN bundle update rails
COPY set_user_permissions.bash /etc/my_init.d/01_set_user_permissions.bash
COPY generate_dh_parameters.bash /etc/my_init.d/02_generate_dh_parameters.bash
COPY rails_startup.bash /etc/my_init.d/03_rails_startup.bash

# Configure NGINX
RUN rm /etc/nginx/sites-enabled/default
COPY webapp.conf /etc/nginx/sites-enabled/webapp.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY /local/path/to/mycert.crt /etc/pki/tls/certs/mycert.crt
COPY /local/path/to/mycert.key /etc/pki/tls/private/mycert.key

RUN rm -f /etc/service/nginx/down

# Compile native support for passenger for Ruby 2.2
RUN sudo -u app passenger-config build-native-support
