# REDMINE

A bash script which use docker-compose to run Redmine PRM service in less than 1 minute, After installation it's includes some tools that may growth at future.

## How to use it:
1- Take clone on ur local 

2- Chmod +x ~/redmine/install.sh

3- ./install.sh

4- It ask for an IP, so enter ur IP

5- The script ask for password.

6- For last step It ask for runnig docker compose. By typing 'y' let it do it, But if u wanna do it later type 'n' and use bellow commands when ever you want:

     cd ~/redmine 
     
     docker compose up -d 
     
7- Everythings reade for using Redmine.



## Tools
For now there are just install_plugin tools that will accessable after installation in ~/redmine/tools/, by running script you can enter an url as imput  and the script will install your plugin by itself.
