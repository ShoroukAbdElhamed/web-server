#!/bin/bash

#Coloring
Color_Off='\033[0m'       # Text Reset
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Cyan='\033[0;36m'         # Cyan

#Installing and configuring nginx
function add-nginx
{
	ret_val=0 #return value of the fuction
	firewall=1 #state of firewall
	declare -i count #just a variable to work as counter
	declare -i num
	count=0 #initialization
	printf "\nChoose your Environment: \n 1-Redhat \n 2-Ubutu\n"

	#Read a choice from user
	read envir
		
	case $envir in  
		1)  
			#Installating-on-Redhat
			echo -e "\nInstalling Nginx..." 
			wget https://nginx.org/packages/rhel/7/x86_64/RPMS/nginx-1.10.3-1.el7.ngx.x86_64.rpm >/dev/null 2>&1
			rpm -ivh nginx-1.10.3-1.el7.ngx.x86_64.rpm >/dev/null 2>&1
			
			#Adding nginx to the allowed services on firewall
			firewall-cmd --permanent --add-service=http >/dev/null 2>&1
			if [ $? -eq 0 ]
			then
				firewall=0 #command successeded 
			fi
			firewall-cmd --reload >/dev/null 2>&1
			
			#Checks if all went well with firewall
			if [ $? -eq 0 ]
			then
				firewall=0 #working
			fi
			;;
		2)
			#Installating-on-Ubuntu
			echo -e "\nInstalling Nginx..."
			apt-get update
			apt-get upgrade
			apt-get install nginx ufw -y
			
			#Adding nginx to the allowed services on firewall
			ufw enable >/dev/null 2>&1
			ufw default allow outgoing >/dev/null 2>&1
			ufw default deny incoming >/dev/null 2>&1
			ufw allow ssh comment 'Open access OpenSSH port 22' >/dev/null 2>&1
			ufw allow 53 comment 'open tcp and udp port 53 for dns' >/dev/null 2>&1
			ufw allow https comment 'Open all to access Nginx port 443' >/dev/null 2>&1
			ufw allow http comment 'Open access Nginx port 80' >/dev/null 2>&1
			ufw reload >/dev/null 2>&1
			#Checks if all went well with firewall
			if [ $? -eq 0 ]
			then
				firewall=0
			fi
			;;
        *)      
			#if the user entered invalid number
			printf "$Red \n Invalid choice $Color_Off"	
			;;
        esac

	#Continue to the next step if the first one successeded
	if [ $firewall -eq 0 ]
	then
		echo -e "Starting the server... "
		rm /etc/nginx/conf.d/load.conf 2>/dev/null #removing the old configuration file in case of running the script for a second time
		systemctl stop httpd >/dev/null 2>&1 #Stopping apache if working as that can make a conflict with nginx listening on port 80
		systemctl start nginx >/dev/null 2>&1 #Starting nginx
		systemctl enable nginx >/dev/null 2>&1
			
		#checking on nginx starting
		service nginx status >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			echo -e "$Green \n Success... $Color_Off"
		else
			echo -e "$Red \n Failed... $Color_Off"
			ret_val=21
		fi

		echo -e "\nConfiguring the server..."
		touch /etc/nginx/conf.d/load.conf
		rm /etc/nginx/conf.d/default.conf 2>/dev/null #Removing the default configuration to nginx as it won't be needed

		#Main configuration for a load-balncer in Nginx
		#The added headers are:
		#Host --> make nginx acknowledge which host is being accessed (virtual host in our case)
		#X-Forwarded-For --> make nginx acknowledge which proxy servers that passed this request
		#X-Forwarded-Proto --> identify the protocol that the client used to connect to the load balancer
		#X-Real-IP --> make nginx acknowledge what the real ip address of client is
		
		echo "
		upstream backend {
						 }

		server {
				listen  80 ;
				location / {
				proxy_pass http://backend;
				proxy_set_header Host $host; 
				
				
				proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; 
				proxy_set_header X-Forwarded-Proto $scheme; 
				
				
				proxy_set_header X-Real-IP $remote_addr; 
				
				proxy_buffering off;
				#health_check;
						   }

					}" >/etc/nginx/conf.d/load.conf


		printf "$Cyan \nPlease follow the instructions to set up the configuration of your server\n $Color_Off"

		#Adding Web servers
		printf "How many Web servers you want to balance?"	

		#Read a number from user
		read num		

		printf "\nPlease enter the Servers ips " 
		
		# loop through the number of servers
		if [ $num -gt 0 ]
		then
			while [ $count -lt $num ]
			do
				printf "\nServer ip is : "
				#Read ip from the user
				read ip												
				
				#checking if valid ip
				local  stat=0
				if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] 
				then
					for i in 1 2 3 4
					do
						if [ $(echo "$ip" | cut -d. -f$i) -gt 255  ]; then
							stat=1
						fi
					done
				else
					stat=1
				fi
				
				if [ $stat -eq 0 ]
				then
					#Add the Servers ips to the configuration file
					sed -i "/upstream backend {/ a\server $ip ;" /etc/nginx/conf.d/load.conf
				else
				    printf "$Red Unvalid IP : ($ip)$Color_Off"
					ret_val=22
				fi
				
				count=$((count+1))

			done
		fi

		#Check for the Algorithm
		printf "\nChoose the the Algorithm that you want to apply for balancing:\n 1-Round Robin\n 2-Least connections\n 3-Ip-hashing\n"		

		#Read the type of Algorithm from user
		read algorithm
		
		case "$algorithm" in 
			1)
				#Nothing is needed to be written
				;;   
			2)
				#Add the Least connection Algorithm to the configuration file
				sed -i "/upstream backend {/ a\server least_conn;" /etc/nginx/conf.d/load.conf
				;;
			3)
				#Add the Ip-hash Algorithm to the configuration file
				sed -i "/upstream backend {/ a\server ip_hash;" /etc/nginx/conf.d/load.conf
				;;
			*)  
				#if the user entered unvalid number
				printf "$Red \n Invalid choice $Color_Off"		
				;;
		esac    

		service nginx status >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			systemctl restart nginx >/dev/null 2>&1

		
		fi

	else
		ret_val=23
	fi
	return $ret_val
}


function add-web-server
{
	ret_val=0
	#Checks if configuration file exists
	if [ -f /etc/nginx/conf.d/load.conf ]; then
		echo "Enter the ip you want to add "

		#Read ip pattern from the user
		read user_ip						        
		
		#check if an existing ip
		cat /etc/nginx/conf.d/load.conf | grep "$user_ip" >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			echo "Already exists !"
		else	
			#checking if valid ip
			local  stat=0
			if [[ $user_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] 
			then
				for i in 1 2 3 4
				do
					if [ $(echo "$user_ip" | cut -d. -f$i) -gt 255 ]; then
						stat=1
					fi
				done
			else 
				stat=1
			fi
			
			if [ $stat -eq 0 ]
			then
				#Add a Server ip to the configuration file
				sed -i "/upstream backend {/ a\server $user_ip;" /etc/nginx/conf.d/load.conf  
			else 
				printf "$Red Unvalid IP : ($user_ip) \n $Color_Off"
				ret_val=24

			fi	
				
			service nginx status >/dev/null 2>&1
			if [ $? -eq 0 ]
			then
				systemctl reload nginx >/dev/null 2>&1
			fi
		fi
	else 
		echo -e "$Red \n Nginx configuration file doesn't exist... $Color_Off"
		ret_val=25		
	fi
	return $ret_val
}

function delete-web-server
{
	ret_val=0
	#Checks if configuration file exists
	if [ -f /etc/nginx/conf.d/load.conf ]; then
		echo "Enter the ip you want to delete"

		#Read the ip from the user
		read user_ip		
		
		#check if an existing ip
		cat /etc/nginx/conf.d/load.conf | grep "$user_ip" >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			#Delete that pattern from the configuration file
			sed -i "/$user_ip/d" /etc/nginx/conf.d/load.conf 
			printf "$Green \n Successfully deleted \n$Color_Off"
		else 
			printf "$user_ip  doesn't exist \n $Color_Off"
		fi	
		systemctl reload nginx >/dev/null 2>&1

	else 
		echo -e "$Red \n Nginx configuration file doesn't exist... $Color_Off"
		ret_val=25
	fi
	return $ret_val
} 

function list-all-servers
{
	#Create a temporary file      
	touch /tmp/file_nginx  

	#Checks if configuration file exists
	if [ -f /etc/nginx/conf.d/load.conf ]; then
	   
		#Get all Servers from configuration file and redirect the Servers to that file
		grep "server [0-9]" /etc/nginx/conf.d/load.conf > /tmp/file_nginx        
		
		if [ -s /tmp/file_nginx  ]
		then
			#Replace the (;) in the configuration file with blank space
			sed -i "s/;$//" file  
																	
			#Print the Servers
			echo "Servers are  "
			cat /tmp/file_nginx 
		else
			printf "No servers exists \n"
		fi

	else 
		echo -e "$Red \n Nginx configuration file doesn't exist... $Color_Off"
		ret_val=25
	fi
	return $ret_val

}


# Menu for the options
printf "Choose an option: \n 1-Configure nginx host \n 2-Add a web server \n 3-Delete a web server \n 4-List all members\n"	       

# Read a choice from the user
read choice               

case $choice in
	#Configure and install nginx server
	1) 
			add-nginx				
			;;
			
	#Add a Web-Server to the Load-Balancer list
	2)
			add-web-server
			;;
			
	#Delete a Web-Server from the Load-Balancer list
	3)
			delete-web-server
			;;           
			
	#List all Servers in the Load-Blalancer list
	4)
			list-all-servers
			;;       
			
	#if the user entered unvalid number
	*)      
			printf "$Red \n Invalid choice $Color_Off"	 
			;;
			
esac  


		

