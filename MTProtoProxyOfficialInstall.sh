#!/bin/bash
function GetRandomPort(){
  if ! [ "$INSTALLED_LSOF" == true ];then 
    echo "Installing lsof package. Please wait."
    yum -y -q install lsof
    RETURN_CODE=$?
    if [ $RETURN_CODE -ne 0 ]; then
      echo "$(tput setaf 3)Warning!$(tput sgr 0) lsof package did not installed successfully. The randomized port may be in use."
    else
      INSTALLED_LSOF=true
    fi
  fi
  PORT=$((RANDOM % 16383 + 49152))
  if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
    GetRandomPort
  fi
}
function GetRandomPortLO(){
  if ! [ "$INSTALLED_LSOF" == true ];then 
    echo "Installing lsof package. Please wait."
    yum -y -q install lsof
    RETURN_CODE=$?
    if [ $RETURN_CODE -ne 0 ]; then
      echo "$(tput setaf 3)Warning!$(tput sgr 0) lsof package did not installed successfully. The randomized port may be in use."
    else
      INSTALLED_LSOF=true
    fi
  fi
  PORT_LO=$((RANDOM % 16383 + 49152))
  if lsof -Pi :$PORT_LO -sTCP:LISTEN -t >/dev/null ; then
    GetRandomPortLO
  fi
  if [ $PORT_LO -eq $PORT ]; then
    GetRandomPortLO
  fi
}
function GenerateService(){
  ARGS_STR="-u nobody -p $PORT_LO -H $PORT"
  for i in "${SECRET_ARY[@]}" # Add secrets
  do
    ARGS_STR+=" -S $i"
  done
  if ! [ -z "$TAG" ]; then
    ARGS_STR+=" -P $TAG "
  fi
  NEW_CORE=$(($CPU_CORES-1))
  ARGS_STR+=" -M $NEW_CORE $CUSTOM_ARGS --aes-pwd proxy-secret proxy-multi.conf"
  SERVICE_STR="[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy/objs/bin
ExecStart=/opt/MTProxy/objs/bin/mtproto-proxy $ARGS_STR
Restart=on-failure

[Install]
WantedBy=multi-user.target"
}
#User must run the script as root
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run this script as root"
  exit 1
fi
regex='^[0-9]+$'
clear
if [ -d "/opt/MTProxy" ]; then
  echo "You have already installed MTProxy! What do you want to do?"
  echo "  1) Uninstall Proxy"
  echo "  2) Change TAG"
  echo "  3) Revoke Secret"
  echo "  4) Add Secret"
  echo "  5) Change Worker Numbers"
  echo "  6) Change Custom Arguments"
  echo "  7) Generate Firewalld Rules"
  echo "  *) Exit"
  read -r -p "Please enter a number: " OPTION
  source /opt/MTProxy/objs/bin/mtconfig.conf #Load Configs
  case $OPTION in
    #Uninstall proxy
    1)
      read -r -p "I still keep some packages \"Development Tools\". Do want to uninstall MTProto-Proxy?(y/n) " OPTION
      case $OPTION in
        "y")
          cd /opt/MTProxy || exit 2
          systemctl stop MTProxy
          systemctl disable MTProxy
          firewall-cmd --remove-port="$PORT"/tcp
          firewall-cmd --runtime-to-permanent
          rm -rf /opt/MTProxy
          rm -f /etc/systemd/system/MTProxy.service
          systemctl daemon-reload
          sed -i '\|cd /opt/MTProxy/objs/bin && bash updater.sh|d' /etc/crontab
          systemctl restart crond
          echo "Ok it's done."
          ;;
      esac
    ;;
    #Change TAG
    2)
      if [ -z "$TAG" ]; then
        echo "It looks like your AD TAG is empty. Get the AD TAG at https://t.me/mtproxybot and enter it here:"
      else
        echo "Current tag is $TAG. If you want to remove it, just press enter. Otherwise type the new TAG:"
      fi
      read -r TAG
      cd /etc/systemd/system || exit 2
      systemctl stop MTProxy
      rm MTProxy.service
      GenerateService
      echo "$SERVICE_STR" >> MTProxy.service
      systemctl daemon-reload
      systemctl start MTProxy
      cd /opt/MTProxy/objs/bin/ || exit 2
      sed -i "s/^TAG=.*/TAG=$TAG/" mtconfig.conf
      echo "Done"
    ;;
    #Revoke Secret
    3)
      NUMBER_OF_SECRETS=${#SECRET_ARY[@]}
      if [ "$NUMBER_OF_SECRETS" -le 1 ]; then
        echo "Cannot remove the last secret."
      fi
      echo "Select a secret to revoke:"
      COUNTER=1
      for i in "${SECRET_ARY[@]}"
      do
        echo "  $COUNTER) $i"
        COUNTER=$((COUNTER+1))
      done
      read -r -p "Select a user by it's index to revoke: " USER_TO_REVOKE
      if ! [[ $USER_TO_REVOKE =~ $regex ]] ; then
        echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
        exit 1
      fi
      if [ "$USER_TO_REVOKE" -lt 1 ] || [ "$USER_TO_REVOKE" -gt "$NUMBER_OF_SECRETS" ]; then
        echo "$(tput setaf 1)Error:$(tput sgr 0) Invalid number"
        exit 1
      fi
      USER_TO_REVOKE1=$(($USER_TO_REVOKE-1))
      SECRET_ARY=("${SECRET_ARY[@]:0:$USER_TO_REVOKE1}" "${SECRET_ARY[@]:$USER_TO_REVOKE}")
      cd /etc/systemd/system || exit 2
      systemctl stop MTProxy
      rm MTProxy.service
      GenerateService
      echo "$SERVICE_STR" >> MTProxy.service
      systemctl daemon-reload
      systemctl start MTProxy
      cd /opt/MTProxy/objs/bin/ || exit 2 || exit 2
      SECRET_ARY_STR=${SECRET_ARY[*]}
      sed -i "s/^SECRET_ARY=.*/SECRET_ARY=($SECRET_ARY_STR)/" mtconfig.conf
      echo "Done"
    ;;
    #Add secret
    4)
      echo "Do you want to set secret manually or shall I create a random secret?"
      echo "   1) Manually enter a secret"
      echo "   2) Create a random secret"
      read -r -p "Please select one [1-2]: " -e -i 2 OPTION
      case $OPTION in
        1)
          echo "Enter a 32 character string filled by 0-9 and a-f(hexadecimal): "
          read -r SECRET
          #Validate length
          SECRET="$(echo $SECRET | tr '[A-Z]' '[a-z]')"
          if ! [[ $SECRET =~ ^[0-9a-f]{32}$ ]] ; then
            echo "$(tput setaf 1)Error:$(tput sgr 0) Enter hexadecimal characters and secret must be 32 characters."
            exit 1
          fi
        ;;
        2)
          SECRET="$(hexdump -vn "16" -e ' /1 "%02x"'  /dev/urandom)"
          echo "OK I created one: $SECRET"
        ;;
        *)
        echo "$(tput setaf 1)Invalid option$(tput sgr 0)"
        exit 1
      esac
      SECRET_ARY+=("$SECRET")
      #Add secret to config
      cd /etc/systemd/system || exit 2
      systemctl stop MTProxy
      rm MTProxy.service
      GenerateService
      echo "$SERVICE_STR" >> MTProxy.service
      systemctl daemon-reload
      systemctl start MTProxy
      cd /opt/MTProxy/objs/bin/ || exit 2
      SECRET_ARY_STR=${SECRET_ARY[*]}
      sed -i "s/^SECRET_ARY=.*/SECRET_ARY=($SECRET_ARY_STR)/" mtconfig.conf
      echo "Done"
    ;;
    #Change CPU workers
    5)
      CPU_CORES=$(nproc --all)
      echo "I've detected that your server has $CPU_CORES cores. If you want I can configure proxy to run at all of your cores. This will make the proxy to spawn $CPU_CORES workers. For some reasons, proxy will most likely to fail at more than 16 cores. So please choose a number between 1 and 16."
      read -r -p "Who many workers you want proxy to spawn? " -e -i "$CPU_CORES" CPU_CORES
      if ! [[ $CPU_CORES =~ $regex ]] ; then #Check if input is number
        echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
        exit 1
      fi
      if [ "$CPU_CORES" -gt 16 ] || [ "$CPU_CORES" -lt 1 ]; then #Check range of workers
        echo "$(tput setaf 1)Error:$(tput sgr 0) Enter number between 1 and 16."
        exit 1
      fi
      #Save
      cd /etc/systemd/system || exit 2
      systemctl stop MTProxy
      rm MTProxy.service
      GenerateService
      echo "$SERVICE_STR" >> MTProxy.service
      systemctl daemon-reload
      systemctl start MTProxy
      cd /opt/MTProxy/objs/bin/ || exit 2
      sed -i "s/^CPU_CORES=.*/CPU_CORES=$CPU_CORES/" mtconfig.conf
      echo "Done"
    ;;
    #Change other args
    6)
      echo "If you want to use custom arguments to run the proxy enter them here; Otherwise just press enter."
      read -r -e -i "$CUSTOM_ARGS" CUSTOM_ARGS
      #Save
      cd /etc/systemd/system || exit 2
      systemctl stop MTProxy
      rm MTProxy.service
      GenerateService
      echo "$SERVICE_STR" >> MTProxy.service
      systemctl daemon-reload
      systemctl start MTProxy
      cd /opt/MTProxy/objs/bin/ || exit 2
      sed -i "s/^CUSTOM_ARGS=.*/CUSTOM_ARGS=\"$CUSTOM_ARGS\"/" mtconfig.conf
      echo "Done"
    ;;
    #Firewall rules
    7)
      echo "firewall-cmd --zone=public --add-port=$PORT/tcp"
      echo "firewall-cmd --runtime-to-permanent"
      read -r -p "Do you want to apply these rules?[y/n] " -e -i "y" OPTION
      if [ "$OPTION" == "y" ] ; then
        firewall-cmd --zone=public --add-port="$PORT"/tcp
        firewall-cmd --runtime-to-permanent
        echo "Done"
      fi
    ;;
  esac
  exit
fi
if [ "$#" -ge 3 ]; then
  AUTO=true
  #Check secret
  SECRETS=$3
  SECRET_ARY=(${SECRETS//,/ })
  for i in "${SECRET_ARY[@]}"
  do 
    if ! [[ $i =~ ^[0-9a-f]{32}$ ]] ; then
      echo "$(tput setaf 1)Error:$(tput sgr 0) Enter hexadecimal characters and secret must be 32 characters. Error on secret $i"
      exit 1
    fi
  done
  #Check port
  PORT=$1
  if [[ $PORT -eq -1 ]] ; then #Check random port
    GetRandomPort
    echo "I've selected $PORT as your port."
  fi
  if ! [[ $PORT =~ $regex ]] ; then #Check if the port is valid
    echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
    exit 1
  fi
  if [ "$PORT" -gt 65535 ] ; then
    echo "$(tput setaf 1)Error:$(tput sgr 0): Number must be less than 65536"
    exit 1
  fi
  #Check loopback port
  PORT_LO=$2
  if [[ $PORT_LO -eq -1 ]] ; then #Check random loopback status port
    GetRandomPortLO
    echo "I've selected $PORT_LO as your loopback status port."
  fi
  if ! [[ $PORT_LO =~ $regex ]] ; then #Check if the loopback status port is valid
    echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
    exit 1
  fi
  if [ "$PORT_LO" -gt 65535 ] ; then
    echo "$(tput setaf 1)Error:$(tput sgr 0): Number must be less than 65536"
    exit 1
  fi
  #Check tag
  if [ "$#" -ge 4 ]; then
    TAG=$4
  fi
  CPU_CORES=$(nproc --all)
  CUSTOM_ARGS=""
  ENABLE_UPDATER="y"
  read
else
#Variables
SECRET=""
SECRET_ARY=()
TAG=""
echo "Welcome to MTProto-Proxy auto installer!"
echo "Created by Hirbod Behnam"
echo "I will install mtprotoproxy the official repository"
echo "You can auto install like \"./MTProtoProxyOfficialInstall Port Status_Port Secret [TAG]\""
echo "Source at https://github.com/TelegramMessenger/MTProxy"
echo "Now I will gather some info from you."
echo ""
echo ""
#Proxy Port
read -r -p "Select a port to proxy listen on it (-1 to randomize): " -e -i 443 PORT
if [[ $PORT -eq -1 ]] ; then #Check random port
  GetRandomPort
  echo "I've selected $PORT as your port."
fi
if ! [[ $PORT =~ $regex ]] ; then #Check if the port is valid
  echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
  exit 1
fi
if [ "$PORT" -gt 65535 ] ; then
  echo "$(tput setaf 1)Error:$(tput sgr 0): Number must be less than 65536"
  exit 1
fi
#Status port
read -r -p "Select a port to proxy listen on it (-1 to randomize): " -e -i 8888 PORT_LO
if [[ $PORT_LO -eq -1 ]] ; then #Check random loopback status port
  GetRandomPortLO
  echo "I've selected $PORT_LO as your loopback status port."
fi
if ! [[ $PORT_LO =~ $regex ]] ; then #Check if the loopback status port is valid
  echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
  exit 1
fi
if [ "$PORT_LO" -gt 65535 ] ; then
  echo "$(tput setaf 1)Error:$(tput sgr 0): Number must be less than 65536"
  exit 1
fi
while true; do
  echo "Do you want to set secret manually or shall I create a random secret?"
  echo "   1) Manually enter a secret"
  echo "   2) Create a random secret"
  read -r -p "Please select one [1-2]: " -e -i 2 OPTION
  case $OPTION in
    1)
      echo "Enter a 32 character string filled by 0-9 and a-f(hexadecimal): "
      read -r SECRET
      #Validate length
      SECRET="$(echo $SECRET | tr '[A-Z]' '[a-z]')"
      if ! [[ $SECRET =~ ^[0-9a-f]{32}$ ]] ; then
        echo "$(tput setaf 1)Error:$(tput sgr 0) Enter hexadecimal characters and secret must be 32 characters."
        exit 1
      fi
      ;;
    2)
      SECRET="$(hexdump -vn "16" -e ' /1 "%02x"'  /dev/urandom)"
      echo "OK I created one: $SECRET"
      ;;
    *)
      echo "$(tput setaf 1)Invalid option$(tput sgr 0)"
      exit 1
  esac
  SECRET_ARY+=("$SECRET")
  read -r -p "Do you want to add another secret?(y/n) " -e -i "n" OPTION
  case $OPTION in
    'y')
      ;;
    'n')
      break
      ;;
    *)
      echo "$(tput setaf 1)Invalid option$(tput sgr 0)"
      exit 1
  esac
done
#Now setup the tag
read -r -p "Do you want to setup the advertising tag?(y/n) " -e -i "n" OPTION
case $OPTION in
  'y')
    echo "$(tput setaf 1)Note:$(tput sgr 0) Joined users and admins won't see the channel at very top."
    echo "On telegram, go to @MTProxybot Bot and enter this server's IP and $PORT as port. Then as secret enter $SECRET"
    echo "$(tput setaf 3)Also make sure server time is precise, otherwise the proxy may not work when TAG is set.$(tput sgr 0) You may need to use ntp to sync your system time."
    echo "Bot will give you a string named TAG. Enter it here:"
    read -r TAG
    ;;
  'n')
    ;;
  *)
    echo "$(tput setaf 1)Invalid option$(tput sgr 0)"
    exit 1
esac
#Get CPU Cores
CPU_CORES=$(nproc --all)
echo "I've detected that your server has $CPU_CORES cores. If you want I can configure proxy to run at all of your cores. This will make the proxy to spawn $CPU_CORES workers. For some reasons, proxy will most likely to fail at more than 16 cores. So please choose a number between 1 and 16."
read -r -p "How many workers you want proxy to spawn? " -e -i "$CPU_CORES" CPU_CORES
if ! [[ $CPU_CORES =~ $regex ]] ; then #Check if input is number
  echo "$(tput setaf 1)Error:$(tput sgr 0) The input is not a valid number"
  exit 1
fi
if [ "$CPU_CORES" -gt 16 ] || [ "$CPU_CORES" -lt 1 ]; then #Check range of workers
  echo "$(tput setaf 1)Error:$(tput sgr 0) Enter number between 1 and 16."
  exit 1
fi
#Other arguments
echo "If you want to use custom arguments to run the proxy enter them here; Otherwise just press enter."
read -r CUSTOM_ARGS
#Secret and config updater
read -r -p "Do you want to enable the automatic config updater? I will update \"proxy-secret\" and \"proxy-multi.conf\" each day at midnight(12:00 AM). It's recommended to enable this.[y/n]" -e -i "y" ENABLE_UPDATER
#Install
read -n 1 -s -r -p "Press any key to install..."
clear
fi
#Now install packages
yum -y install epel-release
yum -y install openssl-devel zlib-devel curl ca-certificates sed cronie
yum -y groupinstall "Development Tools"
cd /opt || exit 2
git clone https://github.com/TelegramMessenger/MTProxy
cd MTProxy || exit 2
make #Build the proxy
BUILD_STATUS=$? #Check if build was successful
if [ $BUILD_STATUS -ne 0 ]; then
  echo "$(tput setaf 1)Error:$(tput sgr 0) Build failed with exit code $BUILD_STATUS"
  echo "Deleting the project files..."
  rm -rf /opt/MTProxy
  echo "Done"
  exit 3
fi
cd objs/bin || exit 2
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
STATUS_SECRET=$?
if [ $STATUS_SECRET -ne 0 ]; then
  echo "$(tput setaf 1)Error:$(tput sgr 0) Cannot download proxy-secret from Telegram servers."
fi
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
STATUS_SECRET=$?
if [ $STATUS_SECRET -ne 0 ]; then
  echo "$(tput setaf 1)Error:$(tput sgr 0) Cannot download proxy-multi.conf from Telegram servers."
fi
#Setup mtconfig.conf
touch mtconfig.conf
echo "PORT_LO=$PORT_LO" >> mtconfig.conf
echo "PORT=$PORT" >> mtconfig.conf
echo "CPU_CORES=$CPU_CORES" >> mtconfig.conf
echo "SECRET_ARY=(${SECRET_ARY[*]})" >> mtconfig.conf
echo "TAG=\"$TAG\"" >> mtconfig.conf
echo "CUSTOM_ARGS=\"$CUSTOM_ARGS\"" >> mtconfig.conf
#Setup firewall
echo "Setting firewalld rules"
SETFIREWALL=true
if ! yum -q list installed firewalld &>/dev/null; then
  echo ""
  if [ "$AUTO" = true  ]; then
    OPTION="y"
  else
    read -r -p "Looks like \"firewalld\" is not installed Do you want to install it?(y/n) " -e -i "y" OPTION
  fi
    case $OPTION in
      "y")
        yum -y install firewalld
        systemctl enable firewalld
        ;;
      *)
        SETFIREWALL=false
        ;;
    esac
fi
if [ "$SETFIREWALL" = true ]; then
  systemctl start firewalld
  firewall-cmd --zone=public --add-port="$PORT"/tcp
  firewall-cmd --runtime-to-permanent
fi
#Setup service files
cd /etc/systemd/system || exit 2
touch MTProxy.service
GenerateService
echo "$SERVICE_STR" >> MTProxy.service
systemctl daemon-reload
systemctl start MTProxy
systemctl is-active --quiet MTProxy #Check if service is active
SERVICE_STATUS=$?
if [ $SERVICE_STATUS -ne 0 ]; then
  echo "$(tput setaf 3)Warning: $(tput sgr 0)Building looks successful but the sevice is not running."
  echo "Check status with \"systemctl status MTProxy\""
fi
systemctl enable MTProxy
#Setup cornjob
if [ "$ENABLE_UPDATER" = "y" ]; then
  echo '#!/bin/bash
systemctl stop MTProxy
cd /opt/MTProxy/objs/bin
curl -s https://core.telegram.org/getProxySecret -o proxy-secret1
STATUS_SECRET=$?
if [ $STATUS_SECRET -eq 0 ]; then
  cp proxy-secret1 proxy-secret
fi
rm proxy-secret1
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf1
STATUS_CONF=$?
if [ $STATUS_CONF -eq 0 ]; then
  cp proxy-multi.conf1 proxy-multi.conf
fi
rm proxy-multi.conf1
systemctl start MTProxy
echo "Updater runned at $(date). Exit codes of getProxySecret and getProxyConfig are $STATUS_SECRET and $STATUS_CONF" >> updater.log' >> /opt/MTProxy/objs/bin/updater.sh
  echo "" >> /etc/crontab
  echo "0 0 * * * root cd /opt/MTProxy/objs/bin && bash updater.sh" >> /etc/crontab
  systemctl restart crond
fi
#Show proxy links
tput setaf 3
printf "%`tput cols`s"|tr ' ' '#'
tput sgr 0
echo "These are the links with random padding:"
PUBLIC_IP="$(curl https://api.ipify.org -sS)"
CURL_EXIT_STATUS=$?
if [ $CURL_EXIT_STATUS -ne 0 ]; then
  PUBLIC_IP="YOUR_IP"
fi
for i in "${SECRET_ARY[@]}"
do
  echo "tg://proxy?server=$PUBLIC_IP&port=$PORT&secret=dd$i"
done
