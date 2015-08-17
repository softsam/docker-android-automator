#!/bin/bash

# CONSTANTS
# Automation directory
AUTOMATION_DIR=/automation
# Directory containing the apk to install
APK_DIR=${AUTOMATION_DIR}/apk
# Directory containing the robot framework tests
ROBOT_DIR=${AUTOMATION_DIR}/robot
# Directory containing the output of the tests
OUTPUT_DIR=${AUTOMATION_DIR}/output
# default locale when none is provided
DEFAULT_LOCALE="en"

# Shell colors
RED="\033[31m"
GREEN="\033[32m"
NO_COLOR="\033[0m"


# Parse arguments
parse_arguments()
{
    args=`getopt -l sdk:,devices,prefix:,help,pybot-args:,locales:,arch: s:dp:ha:l:c: $*`
    local parsing_pybot=false
    while true;do
        case $1 in
            -s|--sdk)
                parsing_pybot=false
                sdk_list=`eval echo $2 | tr -s "," "  "`;shift;shift;continue
            ;;
            -d|--devices)
                parsing_pybot=false
                run_on_physical_device="yes";shift;continue
            ;;
            -p|--prefix)
                parsing_pybot=false
                prefix=`eval echo $2`;shift;shift;continue
            ;;
            -h|--help)
                parsing_pybot=false
                show_help;exit;
            ;;
            -a|--pybot-args)
                parsing_pybot=true
                pybot_args=`eval echo "$2"`;shift;shift;continue
            ;;
            -l|--locales)
                parsing_pybot=false
                locales_list=`eval echo "$2" | tr -s "," "  "`;shift;shift;continue
            ;;
            -c|--arch)
                parsing_pybot=false
                architecture=`eval echo "$2"`;shift;shift;continue
            ;;
            --)
               break
            ;;
            *)
               if test -z $1
               then
                   # no more args
                   break
               fi

               if [[ $parsing_pybot = true ]]
               then
                   pybot_args="${pybot_args} `eval echo "$1"`";shift;continue
               else
                   show_help;exit;
              fi
           ;;
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
    echo "    [ -a | -- pybot-args ] Additional custom pybot arguments. Ex: -a \"--variable platform:dev\""
    echo "    [ -l | -- locales ] Tests will run for each given locale. Ex: --locales en,fr,es,ru. If not provided, will run on the default device / emulator locale. Emulators are in en by default."
    echo"     [ -c | --arch ] The architecture of the emulators. Only used when running tests on emulators, 2 values can be provided: arm or x86. Using x86 architecture requires your system to have kvm and support virtualization (not possible if your are using boot2docker). Default is arm (slower but works on all environments)."
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

# Check the requested emulator architecture is supported
check_architecture()
{
    if [[ $architecture == "x86" ]]
    then
        if [ ! -e /dev/kvm ]
        then
            log_error "You must provide the /dev/kvm directory as a volume if you wish to run emulators with x86 architecture. Also, make sure you run the container with the --privileged option."
            exit 3
        fi
        return;
    fi

    if [[ $architecture != "arm" ]]
    then
        log_error "Unsupported architecture. Only x86 and arm are supported."
        exit 4
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
    log_info "Removing containers"
    docker rm -f $docker_android 2> /dev/null 
    docker rm -f $docker_appium 2> /dev/null
    docker rm -f $docker_robot 2> /dev/null
    docker rm -f $docker_vncrecorder 2> /dev/null
}

# Run the tests for all the defined locales
# First argument: the device on which the tests are run
# Second argument: the sdk version of the device / emulator
# Third argument: the output directory of the tests
run_tests_for_all_locales()
{
    local device=$1
    local android_api=$2
    local output_dir=$3

    # backup device locale
    local device_locale=$(get_device_locale $device)
    log_info "Running tests on locales"
    # default locale if none provided
    if [ -z "$locales_list" ]
    then
        locales_list="$DEFAULT_LOCALE"
    fi
    for loc in $locales_list
    do
        change_locale $device $loc
        run_tests $device $android_api $loc $output_dir
    done
    # restore device initial locale
    change_locale $device $device_locale
}

# Run robot framework tests
# First argument: the device on which the tests are run
# Second argument: the sdk version of the device / emulator
# Third argument: the locale of the device /emulator
# Fourth argument: the output directory of the tests
run_tests()
{
    local device=$1
    local android_api=$2
    local locale=$3
    local output_dir=$4
    local pybot_output_dir=${output_dir}/${locale}
    local pybot_args="--log /output/log.html --report /output/report.html --output /output/output.xml --variable automator_android_api:$android_api --variable automator_locale:${locale} $pybot_args"
    # Create output dir for pybot
    mkdir $pybot_output_dir
    log_info "Running robot framework tests on device $device for android api ${android_api} and locale $locale"
    docker pull softsam/robotframework-appium:latest
    docker run --rm --link ${docker_appium}:appium --name $docker_robot -v ${ROBOT_DIR}:/robot -v ${pybot_output_dir}:/output softsam/robotframework-appium:latest $pybot_args .
    if [[ $? != 0 ]]
    then
        tests_in_failure[${#tests_in_failure}]="Tests failed for device $device on API $android_api and locale $locale"
    fi
}

# Change the locale of a device
# First argument: the device on which the locale should be changed
# Second argument: the new locale to set
change_locale()
{
    local device=$1
    local locale=$2
    
    docker exec ${docker_appium} adb shell am start -n com.orange.androidlocales/.ChangeLocaleActivity_ -e language $locale
    log_info "Locale set to $locale on device $device"
}

# Install the locale change tool
# First argument: the device on which the tool should be installed
install_locale_change_tool()
{

    adb start-server &> /dev/null
    adb -s $1 install -r /android_locales.apk 
    adb -s $1 shell pm grant com.orange.androidlocales android.permission.CHANGE_CONFIGURATION
    adb kill-server &> /dev/null
}

# Get the locale of the given device.
# First argument: the device to connect to
get_device_locale()
{
    local device_locale=`docker exec ${docker_appium} adb -s $1 shell getprop persist.sys.language | grep -v "*" | tr -d '\r'`
    echo $device_locale
}

# Main program
sdk_list=""
locales_list=""
run_on_physical_device=""
pybot_args=""
architecture=arm
tests_in_failure=()
parse_arguments $@
check_directory_structure
check_architecture
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
if [ -n "$sdk_list" ]
then
        . run-emulator.sh
	run_tests_on_emulator $sdk_list
fi
cleanup
chmod -R a+w $OUTPUT_DIR
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

