###############################################################################
# Program:
#       AWS Greengrass Raspberry Pi Provisioning Script
#
# Description:
#       This script will perform the necessary installations and configurations
#       to provision a Raspberry Pi as an AWS Greengrass Core device.
#
# Prerequisites:
#       1. You must create security credentials via the AWS console. You will
#          need your Access Key ID & Secret Key for the config file required by
#          this script (you only get one chance to download the Secret Key!).
#
#       2. Set up the new Raspberry Pi:
#            a. Image the SD card using the Raspberry Pi Imager application.
#            b. Create a file called "ssh" in the boot folder of the SD card.
#            c. Insert SD card into the Raspberry Pi and power it on.
#            d. Follow the on-screen prompts to set up the Raspberry Pi.
#              Note: You will need to connect to the internet in order to
#                    update the Raspberry Pi's software. You must update its
#                    software when prompted in order for this script to run
#                    successfully.
#            e. Reboot the Pi.
#
#       3. Create the config file:
#            a. Create a file called "greengrass_setup.cfg". It should set the
#               following variables:
#                   USER_NAME
#                   USER_AWS_ACCESS_KEY_ID
#                   USER_AWS_SECRET_KEY
#                   USER_REGION
#                   THING_NAME
#                   THING_GROUP
#
#       4. After creating the config file, run this script on the Raspberry Pi
#          in the same directory as the config file.
#            a. Copy this script to the Raspberry Pi in the same directory as
#              the config file you created (suggested location: /home/pi/).
#            b. 'chmod' this so that it can be executed.
#            c. Run the script as the default user (pi). Do NOT use sudo when
#              running it.
#
#       5. This script will generate a security certificate which is viewable
#          in the IoT Core Service in AWS Console. You must attach the correct
#          policy to that certificate in order for the Greengrass core software
#          to automatically install Greengrass CLI application.
#            a. Navigate to AWS Console->IoT Core->Security->Certificates.
#            b. Find the certificate you just created.
#            c. Attach the policy named "GreenGrassRequiredPolicy".
#            d. Reboot the Raspberry Pi.
#
# Troubleshooting tips:
#       * Do NOT run this script as root (or using sudo).
#
#       * If you get an "implicit deny" error, make sure that you have given
#         your IAM user the specific privilege which caused the error.
#
#       * If you get an "explicit deny" error, you probably have not
#         successfully performed MFA.
#
# Copyright (c) 2021 Devetry. All rights reserved.
###############################################################################
CONFIG_FILE_NAME="greengrass_setup.cfg"

# Exit if any command fails
set -e

###############################################################################
# On Unset Config Variable Error
#    Called when the script detects that a necessary user configuration
#    variable remained unset after reading in the config file.
###############################################################################
onUnsetConfigVariableError() {
    echo "Please set the variable $1 in the config file ./$CONFIG_FILE_NAME"
    exit 1
}


###############################################################################
# Read Config File
#    Read in the following environment variables from the config file:
#        USER_NAME
#        USER_AWS_ACCESS_KEY_ID
#        USER_AWS_SECRET_KEY
#        USER_REGION
#        THING_NAME
#        THING_GROUP
###############################################################################
readConfigFile() {
    source ./$CONFIG_FILE_NAME
    echo "Successfully read config file: $CONFIG_FILE_NAME."
    echo "Beginning setup using the following configuration (NONE OF THESE SHOULD BE BLANK!):"
    echo "    USER_NAME=$USER_NAME"
    echo "    USER_AWS_ACCESS_KEY_ID=$USER_AWS_ACCESS_KEY_ID"
    echo "    USER_AWS_SECRET_KEY=$USER_AWS_SECRET_KEY"
    echo "    USER_REGION=$USER_REGION"
    echo "    THING_NAME=$THING_NAME"
    echo "    THING_GROUP=$THING_GROUP"
    if [ -z $USER_NAME ]; then
        onUnsetConfigVariableError "USER_NAME"
    elif [ -z $USER_AWS_ACCESS_KEY_ID ]; then
        onUnsetConfigVariableError "USER_AWS_ACCESS_KEY_ID"
    elif [ -z $USER_AWS_SECRET_KEY ]; then
        onUnsetConfigVariableError "USER_AWS_SECRET_KEY"
    elif [ -z $USER_REGION ]; then
        onUnsetConfigVariableError "USER_REGION"
    elif [ -z $THING_NAME ]; then
        onUnsetConfigVariableError "THING_NAME"
    elif [ -z $THING_GROUP ]; then
        onUnsetConfigVariableError "THING_GROUP"
    fi

}


###############################################################################
# Install Prerequisite Libraries
#    Installs libraries needed by this setup & to run AWS GG
###############################################################################
installPrerequisiteLibraries() {
    echo
    echo
    echo "*********************************************************"
    echo "*            Installing necessary libraries"
    echo "*********************************************************"
    echo
    echo

    # Java
    sudo apt install -y default-jdk

    # Pip
    sudo apt-get install -y python3-pip

    # AWS CLI
    pip3 install awscli --upgrade --user
    export PATH=/home/pi/.local/bin:$PATH

    # AWS Greengrass
    pip3 install greengrasssdk
}


###############################################################################
# Configure AWS CLI
#    Configure AWS using the security credentials entered by the user
###############################################################################
configureAWSCLI() {
    echo
    echo
    echo "*********************************************************"
    echo "*                 Configuring AWS CLI"
    echo "*********************************************************"
    echo
    echo

    # Pass the variables directly into the "aws config" command using printf
    printf "${USER_AWS_ACCESS_KEY_ID}\n${USER_AWS_SECRET_KEY}\n${USER_REGION}\njson\n" | aws configure
}


###############################################################################
# Perform MFA
#    Perform Multifactor authentication to in order to install GG core (because
#    Devetry AWS policies requires MFA)
###############################################################################
performMFA() {
    echo
    echo
    echo "*********************************************************"
    echo "*   Preparing to perform Multi-factor Authentication"
    echo "*********************************************************"
    echo
    echo

    # This lists the MFA devices associated with the account
    MFA_LIST_DEVICES_OUTPUT=$(aws iam list-mfa-devices --user-name $USER_NAME)
    COUNT_MFA_DEVICES=$(echo "$MFA_LIST_DEVICES_OUTPUT" | tr " " "\n" | grep -c "SerialNumber")
    MFA_DEVICE_ARN=""

    # Check to see if the AWS account has multiple MFA devices associated with it
    if [ "$COUNT_MFA_DEVICES" -eq "1" ]
    then
        # Just one device, so extract it from the output
        MFA_DEVICE_ARN=$(echo $MFA_LIST_DEVICES_OUTPUT |  sed 's/^.*SerialNumber\"\:\ \"//' | sed 's/\".*//')
    else
        # Need to ask the user which MFA device they would like to use
        echo $MFA_LIST_DEVICES_OUTPUT
        echo -n "Please enter the ARN of the MFA device you wish to use: "
        read MFA_DEVICE_ARN
    fi

    # Get the code from the user's MFA device
    echo -n "Enter the code from your MFA device (e.g. Authy): "
    read MFA_AUTH_CODE

    # Create temporary security credentials
    MFA_OUTPUT=$(aws sts get-session-token --serial-number $MFA_DEVICE_ARN --token-code $MFA_AUTH_CODE)
    export AWS_ACCESS_KEY_ID=$(echo $MFA_OUTPUT | sed 's/^.*AccessKeyId\"\:\ \"//' | sed 's/\".*//')
    export AWS_SECRET_ACCESS_KEY=$(echo $MFA_OUTPUT | sed 's/^.*SecretAccessKey\"\:\ \"//' | sed 's/\".*//')
    export AWS_SESSION_TOKEN=$(echo $MFA_OUTPUT | sed 's/^.*SessionToken\"\:\ \"//' | sed 's/\".*//')
}


###############################################################################
# Install Greengrass
#    Downloads the Greengrass software and installs it. This command is based
#    on the those found on the "Setup a Core Device" page on AWS Console.
###############################################################################
installGreengrass() {
    echo
    echo
    echo "*********************************************************"
    echo "*       Downloading the Greengrass installer"
    echo "*********************************************************"
    echo
    echo
    curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > \
       greengrass-nucleus-latest.zip && \
       unzip greengrass-nucleus-latest.zip -d GreengrassCore
    echo
    echo
    echo "*********************************************************"
    echo "*               Installing Greengrass"
    echo "*********************************************************"
    echo
    echo
    sudo -E java \
        -Droot="/greengrass/v2" \
        -Dlog.store=FILE -jar \
        ./GreengrassCore/lib/Greengrass.jar \
        --aws-region $USER_REGION \
        --thing-name $THING_NAME \
        --thing-group-name $THING_GROUP \
        --component-default-user ggc_user:ggc_group \
        --provision true \
        --setup-system-service true \
        --deploy-dev-tools true
}


printFinalInstructions() {
    echo
    echo
    echo "    ██    ██  ██████  ██    ██      █████  ██████  ███████"
    echo "     ██  ██  ██    ██ ██    ██     ██   ██ ██   ██ ██     "
    echo "      ████   ██    ██ ██    ██     ███████ ██████  █████  "
    echo "       ██    ██    ██ ██    ██     ██   ██ ██   ██ ██     "
    echo "       ██     ██████   ██████      ██   ██ ██   ██ ███████"
    echo
    echo "      █████  ██      ███    ███  ██████  ███████ ████████"
    echo "     ██   ██ ██      ████  ████ ██    ██ ██         ██   "
    echo "     ███████ ██      ██ ████ ██ ██    ██ ███████    ██   "
    echo "     ██   ██ ██      ██  ██  ██ ██    ██      ██    ██   "
    echo "     ██   ██ ███████ ██      ██  ██████  ███████    ██   "
    echo
    echo "             ██████   ██████  ███    ██ ███████"
    echo "             ██   ██ ██    ██ ████   ██ ██     "
    echo "             ██   ██ ██    ██ ██ ██  ██ █████  "
    echo "             ██   ██ ██    ██ ██  ██ ██ ██     "
    echo "             ██████   ██████  ██   ████ ███████"
    echo
    echo "  To complete the creation of your device, you must log into the AWS Console:"
    echo
    echo "  AWS Console"
    echo "     -> IoT Core Service"
    echo "        -> Secure (on the left navigation pane)"
    echo "           -> Certificates"
    echo
    echo "  Find the certificate which was made by this setup script and attach the"
    echo "  policy named \"GreenGrassRequiredPolicy\" to that certificate."
    echo
    echo "  Reboot the Raspberry Pi, and then it should show up as a core device in"
    echo "  IoT Core in AWS Console."
    echo
    echo
}


###############################################################################
# Main
###############################################################################
readConfigFile
installPrerequisiteLibraries
configureAWSCLI
performMFA
installGreengrass
printFinalInstructions
