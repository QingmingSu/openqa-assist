#!/bin/bash

a2mods="headers proxy proxy_http proxy_wstunnel"
for m in $a2mods; do
    (which a2enmod &>/dev/null) || break
    (a2enmod -l 2>&1 | grep -q ${m}) && continue
    echo "a2enmod $m"
    a2enmod $m
done

services="postgresql openqa-gru openqa-webui apache2"
for srv in $services; do
    (systemctl --no-pager status $srv 2>&1 | grep -q "Loaded: loaded") || continue
    echo "restart $srv"
    systemctl restart $srv
done

worker_id=1
while true; do
    worker="openqa-worker@${worker_id}"
    (grep -q "^\[${worker_id}\]" /etc/openqa/workers.ini) || break
    echo "restart $worker"
    systemctl restart ${worker}
    worker_id=$(($worker_id + 1))
done
