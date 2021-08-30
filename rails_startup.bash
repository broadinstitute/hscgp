#!/bin/bash

cd /home/app/webapp
#echo "*** MIGRATING DATABASE ***"
#bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV db:create
#bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV db:migrate
#echo "*** COMPLETED ***"
echo "*** CLEARING TMP CACHE ***"
sudo -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV tmp:clear
echo "*** COMPLETED ***"
if [[ $PASSENGER_APP_ENV = "production" ]]
then
    echo "*** PRECOMPILING ASSETS ***"
    sudo -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:clean
    sudo -u app -H bundle exec rake RAILS_ENV=$PASSENGER_APP_ENV SECRET_KEY_BASE=$SECRET_KEY_BASE assets:precompile
    echo "*** COMPLETED ***"
fi

if [[ -e /home/app/webapp/bin/delayed_job ]]
then
    echo "*** STARTING DELAYED_JOB ***"
    sudo -u app -H bin/delayed_job restart $PASSENGER_APP_ENV -n 6
    echo "*** COMPLETED ***"
fi
