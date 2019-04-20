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

setup_sudoers () {

	echo "www-data ALL=(ALL) NOPASSWD: /sbin/shutdown" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /sbin/iw" | sudo EDITOR='tee -a' visudo
	echo "www-data ALL=(ALL) NOPASSWD: /bin/date" | sudo EDITOR='tee -a' visudo

}

create_folders () {

	mkdir spectrogram-images
	mkdir time-expansion-audio

}

setup_sudoers

git clone https://github.com/richardbeattie/BatCrowd-Detector.git

create_folders
