#!/bin/bash

PYBOT_ARGS="--variable locale:fr"

# CONSTANTS
# Automation directory
AUTOMATION_DIR=~/automation
# Directory containing the apk to install
APK_DIR=${AUTOMATION_DIR}/apk
# Directory containing the robot framework tests
ROBOT_DIR=${AUTOMATION_DIR}/robot
# Directory containing the output of the tests
OUTPUT_DIR=${AUTOMATION_DIR}/output

# Shell colors
RED="\033[31m"
GREEN="\033[32m"
NO_COLOR="\033[0m"


# Parse arguments
parse_arguments()
{
    args=`getopt -l sdk:,devices,prefix:,help s:dp:h $*`
    set -- $args
    while true;do
        case $1 in
            -s|--sdk)
                sdk_list=`eval echo $2 | tr -s "," "  "`;shift;shift;continue
            ;;
            -d|--devices)
                run_on_physical_device="yes";shift;continue
            ;;
            -p|--prefix)
                prefix=`eval echo $2`;shift;shift;continue
            ;;
            -h|--help)
                show_help;exit;
            ;;
            --)
               break
            ;;
            *)
               show_help;exit;
        esac
    done
}

show_help()
{
    echo "Automator tool to run tests on android devices and emulators."
    echo ""
    echo "Provide at least one of the following options:"
    echo "    [ -d | --devices ] Tests will run on every physical device available."
    echo "    [ -s | --sdk ] Tests will run on the given sdk. Ex: --sdk 16,18,22"
    echo "    [ -p | -- prefix ] Prefix you containers inside the automator, to be able to run parallel tests."
    echo "                    Use this option if you wish to run this container several times in parallel, with different names, to avoid conflicts"
    echo "    [ -h | --help ] Display this message."
}

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

    # Create output dir if it does not exist
    if [ ! -d $OUTPUT_DIR ]
    then
        mkdir $OUTPUT_DIR
    fi
}

log_info()
{
    echo -e "${GREEN}${*}${NO_COLOR}"
}

log_error()
{
    echo -e "${RED}${*}${NO_COLOR}"
}

# Cleanup dockers
cleanup()
{
    log_info "Removing previous containers"
    docker rm -f $docker_android 2> /dev/null 
    docker rm -f $docker_appium 2> /dev/null
    docker rm -f $docker_robot 2> /dev/null
    docker rm -f $docker_vncrecorder 2> /dev/null
}

# Run robot framework tests
# First argument: the sdk version of the device / emulator
# Second argument: the output directory of the tests
run_tests()
{
    local device=$1
    local android_api=$2
    local output_dir=$3
    local pybot_args="$PYBOT_ARGS --log /output/log.html --report /output/report.html --output /output/output.xml"
    log_info "Running robot framework tests for android api ${android_api}"
    docker run --rm --link ${docker_appium}:appium --name $docker_robot -v ${ROBOT_DIR}:/robot -v ${output_dir}:/output softsam/robotframework-appium $pybot_args --variable android_api:$android_api .
    if [[ $? != 0 ]]
    then
        tests_in_failure[${#tests_in_failure}]="Tests failed for device $device on API $android_api"
    fi
}

# Main program
sdk_list=""
run_on_physical_device=""
tests_in_failure=()
parse_arguments $@
check_directory_structure
docker_prefix=""
if [[ $prefix != "" ]]
then
    docker_prefix=${prefix}_
fi
docker_appium=${docker_prefix}appium
docker_android=${docker_prefix}android
docker_robot=${docker_prefix}robot
docker_vncrecorder=${docker_prefix}vncrecorder
cleanup
if [[ $run_on_physical_device = "yes" ]]
then
        . run-devices.sh
	run_tests_on_all_physical_devices
fi
if [ -n $sdk_list ]
then
        . run-emulator.sh
	run_tests_on_emulator $sdk_list
fi
cleanup
if [ ${#tests_in_failure} -ne 0 ]
then
    log_error "There are tests in failure"
    for error in "${tests_in_failure[@]}"
    do
        log_error $error
    done
    exit 1
fi

exit 0

