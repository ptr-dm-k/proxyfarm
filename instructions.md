1. install armbian on sd card
2. install card into orangepi zero3 (pc)
3. apt install network-manager
4. apt install openvpn
    copy configs into /etc/openvpn/client/orangepi.conf
    add: pull-filter ignore "redirect-gateway" to conf
    systemctl restart openvpn-client@orangepi
    systemctl status openvpn-client@orangepi
5. upload connection settings client.ovpn and copy/move it to openvpn 
6. apt install modemmanager
7. mmcli -L
8. apt install apache2-utils -y
    htpasswd -c /etc/squid/passwd proxyuser
    >123_WWqWErrrPbG




<!-- nmlci handy commands -->

