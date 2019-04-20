#The BatCrowd-Detector setup Script
#It does the following
# 1. Edits your sudeors file to allow the webinterface to
#		a) Change the time
#		b) Shutdown the Raspberry Pi
#		c) Add new wifi networks
# 2. Clones the BatCrowd repository
# 3. Creates the neccessary folders
#		a) A folder for all the spectrograms
#		b) A folder for all the time expansion audio

PURPLE='\033[0;35m'
GREEN='\033[0;32m'
NC='\033[0m'

read -r -d '' HOSTAPD_CONFIG << EOM
			#2.4GHz setup wifi 80211 b,g,n
			interface=wlan0
			driver=nl80211
			ssid=BatCrowd
			hw_mode=g
			channel=8
			wmm_enabled=0
			macaddr_acl=0
			auth_algs=1 8
			ignore_broadcast_ssid=0
			wpa=2
			wpa_passphrase=BatCrowd
			wpa_key_mgmt=WPA-PSK
			wpa_pairwise=CCMP TKIP
			rsn_pairwise=CCMP

			#80211n - Change GB to your WiFi country code
			country_code=IE
			ieee80211n=1
			ieee80211d=1
EOM

read -r -d '' DNSMASQ_CONFIG << EOM
			#AutoHotspot config
			interface=wlan0
			bind-dynamic
			server=8.8.8.8
			domain-needed
			bogus-priv
			dhcp-range=10.0.0.2,10.0.0.20,255.255.255.0,12h
EOM

read -r -d '' AUTOHOTSPOT_SERVICE_CONFIG << EOM
		[Unit]
		Description=Automatically generates an internet Hotspot when a valid ssid is not in range
		After=multi-user.target
		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/bin/autohotspotN
		[Install]
		WantedBy=multi-user.target
EOM

read -r -d '' APACHE_VIRTUAL_HOST << EOM
		<VirtualHost *:80>
		 ServerName http://batcrowd.local
		 Redirect permanent / https://batcrowd.local
		</VirtualHost>
EOM

setup_sudoers () {

	echo "www-data ALL=(ALL) NOPASSWD: /sbin/shutdown" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /sbin/iw" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /bin/date" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /usr/bin/aplay" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /usr/bin/arecord" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /usr/bin/pkill" | sudo EDITOR='tee -a' visudo

}

create_folders () {

	sudo mkdir spectrogram-images
	sudo mkdir time-expansion-audio

}

install_packages() {

	sudo apt-get update
	sudo apt-get upgrade
	sudo apt-get install git sox apache2 php libapache2-mod-php php7.0-sqlite3 -y

	#Install Composer
	curl -sS https://getcomposer.org/installer | php
	sudo mv composer.phar /usr/local/bin/composer

}

setup auto_hotspot() {

	#Install the libraries
	sudo apt-get install hostapd dnsmasq -y
	sudo systemctl disable hostapd
	sudo systemctl disable dnsmasq

	#We need to unmask hostapd
	sudo systemctl unmask hostapd Leislers

	#Edit the hostapd.conf file
	sudo touch /etc/hostapd/hostapd.conf
	sudo chmod 777 /etc/hostapd/
	sudo chmod 666 /etc/hostapd/hostapd.conf
	sudo echo "$HOSTAPD_CONFIG" > /etc/hostapd/hostapd.conf

	#Add the new .conf file to hostapd settings
	sudo sed -i -e 's@#DAEMON_CONF=""@DAEMON_CONF="/etc/hostapd/hostapd.conf"@g' /etc/default/hostapd

	#Edit dnsmasq.conf file
	sudo echo "$DNSMASQ_CONFIG" >> /etc/dnsmasq.conf

	#Enable port-forwarding for internet over internet
	sudo sed -i -e 's@#net.ipv4.ip_forward=1@net.ipv4.ip_forward=1@g' /etc/sysctl.conf

	#Ensure that the autohotspot script takes over when wifi is on/off
	sudo echo "nohook wpa_supplicant" >> /etc/dhcpcd.conf

	#Create & enable the autohotspot service
	sudo touch /etc/systemd/system/autohotspot.service
	sudo chmod 666 /etc/systemd/system/autohotspot.service
	sudo echo "$AUTOHOTSPOT_SERVICE_CONFIG" > /etc/systemd/system/autohotspot.service
	sudo systemctl enable autohotspot.service

	#Download the autohotspot Script
	sudo wget -O /usr/bin/autohotspotN http://www.raspberryconnect.com/images/autohotspotN/autohotspotn-95-4/autohotspotN.txt
	sudo chmod +x /usr/bin/autohotspotN

}

setup_audio_card () {

	#Enable the driver
	sudo sh -c "echo 'dtoverlay=rpi-cirrus-wm5102' >> /boot/config.txt"
	sudo sed -i -e 's@dtparam=audio=on@#dtparam=audio=on@g' /boot/config.txt

	#Setup module dependencies
	sudo touch /etc/modprobe.d/cirrus.conf
	sudo sh -c "echo 'softdep arizona-spi pre: arizona-ldo1' > /etc/modprobe.d/cirrus.conf"

	#Download use_case_scripts
	cd /home/pi
	mkdir bin
	cd bin
	wget http://www.horus.com/~hias/tmp/cirrus/cirrus-ng-scripts.tgz
	tar zxf cirrus-ng-scripts.tgz
	rm cirrus-ng-scripts.tgz

	#Change rc.local so card is setup on boot
	sudo sed -i -e 's@exit 0@/home/pi/bin/Playback_to_Speakers.sh@g' /etc/rc.local
	sudo sh -c "echo '/home/pi/bin/Record_from_Headset.sh' >> /etc/rc.local"
	sudo sh -c "echo 'exit 0' >> /etc/rc.local"


}

install_batcrowd () {

	cd /var/www/html

	sudo rm *

	sudo -u www-data git clone https://github.com/richardbeattie/BatCrowd-Detector.git .

	create_folders

	composer install

	sudo chown -R www-data database

}

device_configeration () {

	#Change the hostname
	sudo sed -i -e 's@raspberrypi@batcrowd@g' /etc/hostname
	sudo sed -i -e 's@raspberrypi@batcrowd@g' /etc/hosts

	#Add www-data to audio group

	sudo usermod -a -G audio www-data

}

setup_ssl_apache () {

	echo -e "${PURPLE}Setting up SSL for the web-interface. Please answer the following questions...."

	sudo mkdir /etc/apache2/ssl

	sudo openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -out /etc/apache2/ssl/server.crt -keyout /etc/apache2/ssl/server.key

	sudo a2enmod ssl

	sudo ln -s /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-enabled/000-default-ssl.conf

	sudo sed -i -e 's@/etc/ssl/certs/ssl-cert-snakeoil.pem@/etc/apache2/ssl/server.crt@g' /etc/apache2/sites-enabled/000-default-ssl.conf

	sudo sed -i -e 's@SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key@SSLCertificateKeyFile /etc/apache2/ssl/server.key@g' /etc/apache2/sites-enabled/000-default-ssl.conf

	sudo sed -i -e 's@</VirtualHost>@ServerName http://batcrowd.local@g' /etc/apache2/sites-enabled/000-default.conf
	sudo sh -c "echo 'Redirect permanent / https://batcrowd.local/' >> /etc/apache2/sites-enabled/000-default.conf"
	sudo sh -c "echo '</VirtualHost>' >> /etc/apache2/sites-enabled/000-default.conf"

	sudo service apache2 restart

	echo -e "${PURPLE}Your SSL certificate has been successfully setup"

}

sudo apt-get purge dns-root-data -y

setup_sudoers

install_packages

install_batcrowd
