#!/bin/bash

# Automation directory
AUTOMATION_DIR=~/automation
PYBOT_ARGS="--variable locale:fr"
ANDROID_API=19

# Directory containing the apk to install
APK_DIR=${AUTOMATION_DIR}/apk
# Directory containing the robot framework tests
ROBOT_DIR=${AUTOMATION_DIR}/robot
# Directory containing the VNC recorded videos
VNC_DIR=${AUTOMATION_DIR}/vnc


# Shell colors
RED="\033[31m"
GREEN="\033[32m"
NO_COLOR="\033[0m"

# Check directories are created
check_directory_structure()
{
    if [ ! -d $APK_DIR ]
    then
        echo "${RED}The directory $APK_DIR does not exist. Create it and put the apk to test in it.${NO_COLOR}"
        exit 1
    fi

    if [ ! -d $ROBOT_DIR ]
    then
        echo "${RED}The directory $ROBOT_DIR does not exist. Create it and put the robot framework test code in it.${NO_COLOR}"
        exit 2
    fi

    if [ ! -d $VNC_DIR ]
    then
        mkdir $VNC_DIR
    fi
}

log_info()
{
    echo -e "${GREEN}${1}${NO_COLOR}"
}

log_error()
{
    echo -e "${RED}${1}${NO_COLOR}"
}

# Cleanup dockers
cleanup()
{
    log_info "Removing previous containers"
    docker rm -f android 2> /dev/null 
    docker rm -f appium 2> /dev/null
    docker rm -f robot 2> /dev/null
    docker rm -f vncrecorder 2> /dev/null
}

# Run emulator
run_emulator()
{
    log_info "Starting emulator"
    docker run -d -p 5555:5555 -p 5900:5900 --name android softsam/android-${ANDROID_API}
}

# Run appium server
run_appium_server()
{
    log_info "Starting appium server"
    docker run -d --link android:appium2android -p 4723:4723 --name appium -e APPIUM_ARGS="" -v ${APK_DIR}:/apk softsam/appium
}

wait_for_emulator()
{
    bootanim=""
    until [[ "$bootanim" =~ "stopped" ]]; do
       bootanim=`docker exec appium adb -e shell getprop init.svc.bootanim 2>&1`
       echo "Waiting for emulator to start...$bootanim"
       sleep 1
    done
}

# Connect appium & emulator
connect_appium_to_emulator()
{
	log_info "Connect appium to emulator"
    docker exec -i -t appium adb connect android:5555
}

# Run robot framework tests
run_tests()
{
    log_info "Running robot framework tests"
    docker run --link appium:robot2appium --name robot -v ${ROBOT_DIR}:/robot softsam/robotframework-appium $PYBOT_ARGS .
}

start_recording()
{
    log_info "Starting video recording"
    docker run -d --link android:vncrecorder2android --name vncrecorder -v ${VNC_DIR}:/vnc softsam/vncrecorder -o /vnc/record.flv android
}

stop_recording()
{
    log_info "Stopping video recording"
    docker kill -s INT vncrecorder

}

# Main program
check_directory_structure
cleanup
run_emulator
run_appium_server
log_info "Wait for emulator to be ready"
sleep 10
connect_appium_to_emulator
wait_for_emulator
start_recording
run_tests
stop_recording
cleanup

